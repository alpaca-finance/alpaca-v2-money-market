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

  function addFarmPosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _desireToken0Amount,
    uint256 _desireToken1Amount,
    uint256 _minLpReceive
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    LibLYF01.LPConfig memory lpConfig = lyfDs.lpConfigs[_lpToken];

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    uint256 _token0DebtShareId = lyfDs.debtShareIds[_token0][_lpToken];
    uint256 _token1DebtShareId = lyfDs.debtShareIds[_token1][_lpToken];

    // accrue existing debt for healthcheck
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    // accrue new borrow debt
    LibLYF01.accrueDebtShareInterest(_token0DebtShareId, lyfDs);
    LibLYF01.accrueDebtShareInterest(_token1DebtShareId, lyfDs);

    // 1. get token from collat (underlying and ib if possible), borrow if not enough
    _removeCollatWithIbAndBorrow(_subAccount, _token0, _lpToken, _desireToken0Amount, lyfDs);
    _removeCollatWithIbAndBorrow(_subAccount, _token1, _lpToken, _desireToken1Amount, lyfDs);

    // 2. Check min debt size

    LibLYF01.validateMinDebtSize(_subAccount, _token0DebtShareId, lyfDs);
    LibLYF01.validateMinDebtSize(_subAccount, _token1DebtShareId, lyfDs);

    // 3. send token to strat
    IERC20(_token0).safeTransfer(lpConfig.strategy, _desireToken0Amount);
    IERC20(_token1).safeTransfer(lpConfig.strategy, _desireToken1Amount);

    // 4. compose lp
    uint256 _lpReceived = IStrat(lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _desireToken0Amount,
      _desireToken1Amount,
      _minLpReceive
    );

    // 5. deposit to masterChef
    LibLYF01.depositToMasterChef(_lpToken, lpConfig.masterChef, lpConfig.poolId, _lpReceived);

    // 6. add it to collateral
    LibLYF01.addCollat(_subAccount, _lpToken, _lpReceived, lyfDs);

    // 7. health check on sub account
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }
    emit LogAddFarmPosition(msg.sender, _subAccountId, _lpToken, _lpReceived);
  }

  function directAddFarmPosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _desireToken0Amount,
    uint256 _desireToken1Amount,
    uint256 _minLpReceive,
    uint256 _token0AmountIn,
    uint256 _token1AmountIn
  ) external nonReentrant {
    if (_token0AmountIn > _desireToken0Amount || _token1AmountIn > _desireToken1Amount) {
      revert LYFFarmFacet_BadInput();
    }

    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    LibLYF01.LPConfig memory _lpConfig = lyfDs.lpConfigs[_lpToken];

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    LibLYF01.accrueDebtShareInterest(lyfDs.debtShareIds[_token0][_lpToken], lyfDs);
    LibLYF01.accrueDebtShareInterest(lyfDs.debtShareIds[_token1][_lpToken], lyfDs);

    // 1. if desired amount exceeds provided amount, get token from collat (underlying and ib if possible), borrow if not enough
    _removeCollatWithIbAndBorrow(_subAccount, _token0, _lpToken, _desireToken0Amount - _token0AmountIn, lyfDs);
    _removeCollatWithIbAndBorrow(_subAccount, _token1, _lpToken, _desireToken1Amount - _token1AmountIn, lyfDs);

    // 2. send token to strat
    IERC20(_token0).safeTransferFrom(msg.sender, _lpConfig.strategy, _token0AmountIn);
    IERC20(_token1).safeTransferFrom(msg.sender, _lpConfig.strategy, _token1AmountIn);
    IERC20(_token0).safeTransfer(_lpConfig.strategy, _desireToken0Amount - _token0AmountIn);
    IERC20(_token1).safeTransfer(_lpConfig.strategy, _desireToken1Amount - _token1AmountIn);

    // 3. compose lp
    uint256 _lpReceived = IStrat(_lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _desireToken0Amount,
      _desireToken1Amount,
      _minLpReceive
    );

    // 4. deposit to masterChef
    LibLYF01.depositToMasterChef(_lpToken, _lpConfig.masterChef, _lpConfig.poolId, _lpReceived);

    // 5. add it to collateral
    LibLYF01.addCollat(_subAccount, _lpToken, _lpReceived, lyfDs);

    // 6. health check on sub account
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }
    emit LogAddFarmPosition(msg.sender, _subAccountId, _lpToken, _lpReceived);
  }

  function reducePosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount,
    uint256 _amount0Out,
    uint256 _amount1Out
  ) external nonReentrant {
    // todo: should revinvest here before anything
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    ReducePositionLocalVars memory _vars;

    _vars.subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

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

    if (_token0Return < _amount0Out || _token1Return < _amount1Out) {
      revert LYFFarmFacet_TooLittleReceived();
    }

    // 3. Repay debt
    _repayDebt(_vars.subAccount, _vars.token0, _vars.debtShareId0, _token0Return - _amount0Out, lyfDs);
    _repayDebt(_vars.subAccount, _vars.token1, _vars.debtShareId1, _token1Return - _amount1Out, lyfDs);

    if (!LibLYF01.isSubaccountHealthy(_vars.subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }

    // 4. Transfer remaining back to user
    if (_amount0Out > 0) {
      IERC20(_vars.token0).safeTransfer(msg.sender, _amount0Out);
    }
    if (_amount1Out > 0) {
      IERC20(_vars.token1).safeTransfer(msg.sender, _amount1Out);
    }
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

    // remove debt as much as possible
    uint256 _actualRepayAmount = _repayDebtWithShare(_subAccount, _token, _debtShareId, _debtShareToRepay, lyfDs);

    // transfer only amount to repay
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);
    // update reserves of the token. This will impact the outstanding balance
    lyfDs.reserves[_token] += _actualRepayAmount;
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
    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    uint256 _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);

    // repay maxmimum debt
    _debtShareToRepay = _debtShareToRepay > _debtShare ? _debtShare : _debtShareToRepay;

    if (_debtShareToRepay > 0) {
      uint256 _oldDebtShare = lyfDs.debtShares[_debtShareId];
      uint256 _oldDebtValue = lyfDs.debtValues[_debtShareId];

      uint256 _repayAmount = LibShareUtil.shareToValue(_debtShareToRepay, _oldDebtValue, _oldDebtShare);

      // remove collat as much as possible
      uint256 _collatRemoved = LibLYF01.removeCollateral(_subAccount, _token, _repayAmount, lyfDs);
      // remove debt as much as possible
      uint256 _actualRepayAmount = _repayDebt(_subAccount, _token, _debtShareId, _collatRemoved, lyfDs);

      emit LogRepayWithCollat(msg.sender, _subAccountId, _token, _debtShareId, _actualRepayAmount);
    }
  }

  function _removeDebt(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRemove,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _repayAmount) {
    if (lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId) > 0) {
      uint256 _oldDebtShare = lyfDs.debtShares[_debtShareId];
      uint256 _oldDebtValue = lyfDs.debtValues[_debtShareId];

      // update user debtShare
      lyfDs.subAccountDebtShares[_subAccount].updateOrRemove(_debtShareId, _oldSubAccountDebtShare - _shareToRemove);

      // update over collat debtShare
      _repayAmount = LibShareUtil.shareToValue(_shareToRemove, _oldDebtValue, _oldDebtShare);

      lyfDs.debtShares[_debtShareId] -= _shareToRemove;
      lyfDs.debtValues[_debtShareId] -= _repayAmount;

      // emit event
      emit LogRemoveDebt(_subAccount, _debtShareId, _shareToRemove, _repayAmount);
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

  function _repayDebt(
    address _subAccount,
    address _token,
    uint256 _debtShareId,
    uint256 _repayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _actualRepayAmount) {
    uint256 _oldSubAccountDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);

    uint256 _shareToRemove = LibShareUtil.valueToShare(
      _repayAmount,
      lyfDs.debtShares[_debtShareId],
      lyfDs.debtValues[_debtShareId]
    );

    _shareToRemove = _oldSubAccountDebtShare > _shareToRemove ? _shareToRemove : _oldSubAccountDebtShare;

    _actualRepayAmount = _removeDebt(_subAccount, _debtShareId, _oldSubAccountDebtShare, _shareToRemove, lyfDs);

    LibLYF01.validateMinDebtSize(_subAccount, _debtShareId, lyfDs);

    emit LogRepay(_subAccount, _token, msg.sender, _actualRepayAmount);
  }

  function _repayDebtWithShare(
    address _subAccount,
    address _token,
    uint256 _debtShareId,
    uint256 _debtShareToRepay,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _actualRepayAmount) {
    uint256 _oldSubAccountDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);

    uint256 _actualShareToRepay = LibFullMath.min(_oldSubAccountDebtShare, _debtShareToRepay);

    _actualRepayAmount = _removeDebt(_subAccount, _debtShareId, _oldSubAccountDebtShare, _actualShareToRepay, lyfDs);

    LibLYF01.validateMinDebtSize(_subAccount, _debtShareId, lyfDs);

    emit LogRepay(_subAccount, _token, msg.sender, _actualRepayAmount);
  }

  function accrueInterest(address _token, address _lpToken) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    LibLYF01.accrueDebtShareInterest(_debtShareId, lyfDs);
  }
}
