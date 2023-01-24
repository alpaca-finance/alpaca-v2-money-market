// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { ILYFFarmFacet } from "../interfaces/ILYFFarmFacet.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract LYFFarmFacet is ILYFFarmFacet {
  using LibSafeToken for IERC20;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogRemoveDebt(
    address indexed _subAccount,
    uint256 indexed _debtShareId,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogAddFarmPosition(
    address indexed _account,
    uint256 indexed _subAccountId,
    address indexed _lpToken,
    uint256 _lpAmount
  );

  event LogRepay(address indexed _subAccount, address _token, address _caller, uint256 _actualRepayAmount);

  event LogRepayWithCollat(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token,
    uint256 _debtShareId,
    uint256 _actualRepayAmount
  );
  event LogReducePosition(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token0,
    address _token1,
    uint256 _repaidToken0Amount,
    uint256 _repaidToken1Amount,
    uint256 _returnedToken0Amount,
    uint256 _returnedToken1Amount
  );

  struct NewAddFarmPositionLocalVars {
    uint256 amount0ToRemoveCollat;
    uint256 amount1ToRemoveCollat;
    uint256 token0AmountFromCollat;
    uint256 token1AmountFromCollat;
    uint256 token0AmountFromIbCollat;
    uint256 token1AmountFromIbCollat;
    uint256 lpReceived;
  }

  struct ReducePositionLocalVars {
    address subAccount;
    address token0;
    address token1;
    uint256 debtShareId0;
    uint256 debtShareId1;
    uint256 debt0ToRepay;
    uint256 debt1ToRepay;
    uint256 debtShare0ToRepay;
    uint256 debtShare1ToRepay;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function newAddFarmPosition(ILYFFarmFacet.AddFarmPositionInput calldata _input) external nonReentrant {
    if (
      _input.desireToken0Amount < _input.token0ToBorrow + _input.token0AmountIn ||
      _input.desireToken1Amount < _input.token1ToBorrow + _input.token1AmountIn
    ) {
      revert LYFFarmFacet_BadInput();
    }

    // prepare data
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    LibLYF01.LPConfig memory _lpConfig = lyfDs.lpConfigs[_input.lpToken];
    NewAddFarmPositionLocalVars memory _vars;
    address _subAccount = LibLYF01.getSubAccount(msg.sender, _input.subAccountId);
    address _token0 = ISwapPairLike(_input.lpToken).token0();
    address _token1 = ISwapPairLike(_input.lpToken).token1();
    uint256 _token0DebtShareId = lyfDs.debtShareIds[_token0][_input.lpToken];
    uint256 _token1DebtShareId = lyfDs.debtShareIds[_token1][_input.lpToken];

    // accrue existing debt to correctly account for interest during health check
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    // accrue debt that is going to be borrowed which is not yet in subAccount
    LibLYF01.accrueDebtShareInterest(_token0DebtShareId, lyfDs);
    LibLYF01.accrueDebtShareInterest(_token1DebtShareId, lyfDs);

    // borrow and validate min debt size
    LibLYF01.borrow(_subAccount, _token0, _input.lpToken, _input.token0ToBorrow, lyfDs);
    LibLYF01.borrow(_subAccount, _token1, _input.lpToken, _input.token1ToBorrow, lyfDs);

    LibLYF01.validateMinDebtSize(_subAccount, _token0DebtShareId, lyfDs);
    LibLYF01.validateMinDebtSize(_subAccount, _token1DebtShareId, lyfDs);

    // transfer user tokens to strategy to prepare for lp composition
    // TODO: use pull token
    IERC20(_token0).safeTransferFrom(msg.sender, _lpConfig.strategy, _input.token0AmountIn);
    IERC20(_token1).safeTransferFrom(msg.sender, _lpConfig.strategy, _input.token1AmountIn);

    // calculate collat amount to remove
    unchecked {
      _vars.amount0ToRemoveCollat = _input.desireToken0Amount - _input.token0ToBorrow - _input.token0AmountIn;
      _vars.amount1ToRemoveCollat = _input.desireToken1Amount - _input.token1ToBorrow - _input.token1AmountIn;
    }

    // remove normal collat first
    _vars.token0AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token0, _vars.amount0ToRemoveCollat, lyfDs);
    _vars.token1AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token1, _vars.amount1ToRemoveCollat, lyfDs);

    // remove ib collat if normal collat removed not satisfy desired collat amount
    _vars.token0AmountFromIbCollat = LibLYF01.removeIbCollateral(
      _subAccount,
      _token0,
      lyfDs.moneyMarket.getIbTokenFromToken(_token0),
      _vars.amount0ToRemoveCollat - _vars.token0AmountFromCollat,
      lyfDs
    );
    _vars.token1AmountFromIbCollat = LibLYF01.removeIbCollateral(
      _subAccount,
      _token1,
      lyfDs.moneyMarket.getIbTokenFromToken(_token1),
      _vars.amount1ToRemoveCollat - _vars.token1AmountFromCollat,
      lyfDs
    );

    // revert if amount from collat removal less than desired collat amount
    unchecked {
      if (
        _vars.amount0ToRemoveCollat > _vars.token0AmountFromCollat + _vars.token0AmountFromIbCollat ||
        _vars.amount1ToRemoveCollat > _vars.token1AmountFromCollat + _vars.token1AmountFromIbCollat
      ) {
        revert LYFFarmFacet_CollatNotEnough();
      }
    }

    // send token to strat to prepare for lp composition
    // total amount sent to strategy = amountIn + amountBorrowed + amountCollatRemoved = desiredAmount
    IERC20(_token0).safeTransfer(_lpConfig.strategy, _input.token0ToBorrow + _vars.amount0ToRemoveCollat);
    IERC20(_token1).safeTransfer(_lpConfig.strategy, _input.token1ToBorrow + _vars.amount1ToRemoveCollat);

    // compose lp
    _vars.lpReceived = IStrat(_lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _input.lpToken,
      _input.desireToken0Amount,
      _input.desireToken1Amount,
      _input.minLpReceive
    );

    // deposit to masterChef
    LibLYF01.depositToMasterChef(_input.lpToken, _lpConfig.masterChef, _lpConfig.poolId, _vars.lpReceived);

    // add lp received from composition back to collateral
    LibLYF01.addCollat(_subAccount, _input.lpToken, _vars.lpReceived, lyfDs);

    // health check
    // revert in case that lp collateralFactor is less than removed collateral's
    // or debt exceed borrowing power by borrowing too much
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }

    emit LogAddFarmPosition(msg.sender, _input.subAccountId, _input.lpToken, _vars.lpReceived);
  }

  function reducePosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount,
    uint256 _minAmount0Out,
    uint256 _minAmount1Out
  ) external nonReentrant {
    // todo: should revinvest here before anything
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    ReducePositionLocalVars memory _vars;

    _vars.subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    LibLYF01.accrueDebtSharesOf(_vars.subAccount, lyfDs);

    if (lyfDs.tokenConfigs[_lpToken].tier != LibLYF01.AssetTier.LP) {
      revert LYFFarmFacet_InvalidAssetTier();
    }

    LibLYF01.LPConfig memory _lpConfig = lyfDs.lpConfigs[_lpToken];

    _vars.token0 = ISwapPairLike(_lpToken).token0();
    _vars.token1 = ISwapPairLike(_lpToken).token1();

    _vars.debtShareId0 = lyfDs.debtShareIds[_vars.token0][_lpToken];
    _vars.debtShareId1 = lyfDs.debtShareIds[_vars.token1][_lpToken];

    LibLYF01.accrueDebtShareInterest(_vars.debtShareId0, lyfDs);
    LibLYF01.accrueDebtShareInterest(_vars.debtShareId1, lyfDs);

    // 1. Remove LP collat
    uint256 _lpFromCollatRemoval = LibLYF01.removeCollateral(_vars.subAccount, _lpToken, _lpShareAmount, lyfDs);

    // 2. Remove from masterchef staking
    IMasterChefLike(_lpConfig.masterChef).withdraw(_lpConfig.poolId, _lpFromCollatRemoval);

    IERC20(_lpToken).safeTransfer(_lpConfig.strategy, _lpFromCollatRemoval);

    (uint256 _token0Return, uint256 _token1Return) = IStrat(_lpConfig.strategy).removeLiquidity(_lpToken);

    // slipage check
    if (_token0Return < _minAmount0Out || _token1Return < _minAmount1Out) {
      revert LYFFarmFacet_TooLittleReceived();
    }

    uint256 _amount0ToRepay = _token0Return - _minAmount0Out;
    uint256 _amount1ToRepay = _token1Return - _minAmount1Out;

    // 3. Remove debt by repay amount
    (_vars.debtShare0ToRepay, _vars.debt0ToRepay) = _getActualDebtToRepay(
      _vars.subAccount,
      _vars.debtShareId0,
      _amount0ToRepay,
      lyfDs
    );
    (_vars.debtShare1ToRepay, _vars.debt1ToRepay) = _getActualDebtToRepay(
      _vars.subAccount,
      _vars.debtShareId1,
      _amount1ToRepay,
      lyfDs
    );

    if (_vars.debtShare0ToRepay > 0) {
      _removeDebtAndValidate(_vars.subAccount, _vars.debtShareId0, _vars.debtShare0ToRepay, _vars.debt0ToRepay, lyfDs);
    }
    if (_vars.debtShare1ToRepay > 0) {
      _removeDebtAndValidate(_vars.subAccount, _vars.debtShareId1, _vars.debtShare1ToRepay, _vars.debt1ToRepay, lyfDs);
    }

    if (!LibLYF01.isSubaccountHealthy(_vars.subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }

    uint256 _amount0Back = _token0Return - _vars.debt0ToRepay;
    uint256 _amount1Back = _token1Return - _vars.debt1ToRepay;

    // 4. Transfer remaining back to user
    if (_amount0Back > 0) {
      IERC20(_vars.token0).safeTransfer(msg.sender, _amount0Back);
    }
    if (_amount1Back > 0) {
      IERC20(_vars.token1).safeTransfer(msg.sender, _amount1Back);
    }

    emit LogReducePosition(
      msg.sender,
      _subAccountId,
      _vars.token0,
      _vars.token1,
      _vars.debt0ToRepay,
      _vars.debt1ToRepay,
      _amount0Back,
      _amount1Back
    );
  }

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];

    LibLYF01.accrueDebtShareInterest(_debtShareId, lyfDs);

    // calculate debt as much as possible
    uint256 _subAccountDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);
    uint256 _actualShareToRepay = LibFullMath.min(_debtShareToRepay, _subAccountDebtShare);

    uint256 _actualRepayAmount = LibShareUtil.shareToValue(
      _actualShareToRepay,
      lyfDs.debtValues[_debtShareId],
      lyfDs.debtShares[_debtShareId]
    );

    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));

    // transfer only amount to repay
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);

    // handle if transfer from has fee
    uint256 _actualReceived = IERC20(_token).balanceOf(address(this)) - _balanceBefore;

    // if transfer has fee then we should repay debt = we received
    if (_actualReceived != _actualRepayAmount) {
      _actualRepayAmount = _actualReceived;
      _actualShareToRepay = LibShareUtil.valueToShare(
        _actualRepayAmount,
        lyfDs.debtShares[_debtShareId],
        lyfDs.debtValues[_debtShareId]
      );
    }

    if (_actualRepayAmount > 0) {
      _removeDebtAndValidate(_subAccount, _debtShareId, _actualShareToRepay, _actualRepayAmount, lyfDs);

      // update reserves of the token. This will impact the outstanding balance
      lyfDs.reserves[_token] += _actualRepayAmount;
    }

    emit LogRepay(_subAccount, _token, msg.sender, _actualRepayAmount);
  }

  function reinvest(address _lpToken) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    if (!lyfDs.reinvestorsOk[msg.sender]) {
      revert LYFFarmFacet_Unauthorized();
    }

    LibLYF01.LPConfig memory _lpConfig = lyfDs.lpConfigs[_lpToken];
    if (_lpConfig.rewardToken == address(0)) {
      revert LYFFarmFacet_InvalidLP();
    }

    LibLYF01.reinvest(_lpToken, 0, _lpConfig, lyfDs);
  }

  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    // check asset tier, if not collat, revert
    if (lyfDs.tokenConfigs[_token].tier != LibLYF01.AssetTier.COLLATERAL) {
      revert LYFFarmFacet_InvalidAssetTier();
    }

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    uint256 _currentDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);

    // min(debtShareToRepay, currentDebtShare)
    uint256 _actualDebtShareToRemove = LibFullMath.min(_debtShareToRepay, _currentDebtShare);

    // prevent repay 0
    if (_actualDebtShareToRemove > 0) {
      // convert debtShare to debtAmount
      uint256 _actualDebtToRemove = LibShareUtil.shareToValue(
        _actualDebtShareToRemove,
        lyfDs.debtValues[_debtShareId],
        lyfDs.debtShares[_debtShareId]
      );

      // if collat is not enough to repay debt, revert
      if (lyfDs.subAccountCollats[_subAccount].getAmount(_token) < _actualDebtToRemove) {
        revert LYFFarmFacet_CollatNotEnough();
      }

      // remove collat from subaccount
      LibLYF01.removeCollateral(_subAccount, _token, _actualDebtToRemove, lyfDs);

      _removeDebtAndValidate(_subAccount, _debtShareId, _actualDebtShareToRemove, _actualDebtToRemove, lyfDs);

      emit LogRepayWithCollat(msg.sender, _subAccountId, _token, _debtShareId, _actualDebtToRemove);
    }
  }

  /// @dev this method should only be called by addFarmPosition context
  /// @param _token only underlying token
  function _removeCollatWithIbAndBorrow(
    address _subAccount,
    address _token,
    address _lpToken,
    uint256 _desireTokenAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    uint256 _tokenAmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token, _desireTokenAmount, lyfDs);
    uint256 _tokenAmountFromIbCollat = LibLYF01.removeIbCollateral(
      _subAccount,
      _token,
      lyfDs.moneyMarket.getIbTokenFromToken(_token),
      _desireTokenAmount - _tokenAmountFromCollat,
      lyfDs
    );
    LibLYF01.borrow(
      _subAccount,
      _token,
      _lpToken,
      _desireTokenAmount - _tokenAmountFromCollat - _tokenAmountFromIbCollat,
      lyfDs
    );
  }

  function _removeDebtAndValidate(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _debtShareToRepay,
    uint256 _debtValueToRepay,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    LibLYF01.removeDebt(_subAccount, _debtShareId, _debtShareToRepay, _debtValueToRepay, lyfDs);

    // validate after remove debt
    LibLYF01.validateMinDebtSize(_subAccount, _debtShareId, lyfDs);
  }

  function accrueInterest(address _token, address _lpToken) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    LibLYF01.accrueDebtShareInterest(_debtShareId, lyfDs);
  }

  function _getActualDebtToRepay(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _desiredRepayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _actualShareToRepay, uint256 _actualToRepay) {
    uint256 _debtValues = lyfDs.debtValues[_debtShareId];
    uint256 _debtShares = lyfDs.debtValues[_debtShareId];

    // debt share of sub account
    _actualShareToRepay = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);
    // Note: precision loss 1 wei when convert share back to value
    // debt value of sub account
    _actualToRepay = LibShareUtil.shareToValue(_actualShareToRepay, _debtValues, _debtShares);

    // if debt in sub account more than desired repay amount, then repay all of them
    if (_actualToRepay > _desiredRepayAmount) {
      _actualToRepay = _desiredRepayAmount;
      // convert desiredRepayAmount to share
      _actualShareToRepay = LibShareUtil.valueToShare(_desiredRepayAmount, _debtShares, _debtValues);
    }
  }
}
