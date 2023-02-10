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

/// @title LYFFarmFacet is dedicated to managing leveraged farming positions
contract LYFFarmFacet is ILYFFarmFacet {
  using LibSafeToken for IERC20;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogAddFarmPosition(
    address indexed _account,
    uint256 indexed _subAccountId,
    address indexed _lpToken,
    uint256 _lpAmount
  );

  event LogRepay(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token,
    address _caller,
    uint256 _actualRepayAmount
  );

  event LogRepayWithCollat(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token,
    uint256 _debtPoolId,
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

  struct ReducePositionLocalVars {
    address subAccount;
    address token0;
    address token1;
    uint256 debtPoolId0;
    uint256 debtPoolId1;
    uint256 debt0ToRepay;
    uint256 debt1ToRepay;
    uint256 debtShare0ToRepay;
    uint256 debtShare1ToRepay;
  }

  struct AddFarmPositionLocalVars {
    address account;
    address subAccount;
    address token0;
    address token1;
    uint256 token0DebtPoolId;
    uint256 token1DebtPoolId;
    uint256 lpReceived;
  }

  struct PrepareTokenToComposeLPLocalVars {
    uint256 amountToRemoveCollat;
    uint256 tokenAmountFromCollat;
    uint256 tokenAmountFromIbCollat;
    uint256 amountToStrat;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice There are 3 source of fund used to fulfill desired amount
  /// 1) borrow (require collateral beforehand)
  /// 2) user supplied
  /// 3) collateral (non-ib token, then ib token if non-ib is not enough)
  function addFarmPosition(ILYFFarmFacet.AddFarmPositionInput calldata _input) external nonReentrant {
    if (
      _input.desiredToken0Amount < _input.token0ToBorrow + _input.token0AmountIn ||
      _input.desiredToken1Amount < _input.token1ToBorrow + _input.token1AmountIn
    ) {
      revert LYFFarmFacet_BadInput();
    }

    AddFarmPositionLocalVars memory _vars;

    // sanity check token ordering. prevent borrow, remove collat for wrong token
    _vars.token0 = ISwapPairLike(_input.lpToken).token0();
    if (_input.token0 != _vars.token0) {
      revert LYFFarmFacet_BadInput();
    }

    // prepare data
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    LibLYF01.LPConfig memory _lpConfig = lyfDs.lpConfigs[_input.lpToken];

    _vars.account = msg.sender;
    _vars.subAccount = LibLYF01.getSubAccount(_vars.account, _input.subAccountId);
    _vars.token1 = ISwapPairLike(_input.lpToken).token1();
    _vars.token0DebtPoolId = lyfDs.debtPoolIds[_vars.token0][_input.lpToken];
    _vars.token1DebtPoolId = lyfDs.debtPoolIds[_vars.token1][_input.lpToken];

    // accrue existing debt to correctly account for interest during health check
    LibLYF01.accrueDebtSharesOf(_vars.subAccount, lyfDs);

    // accrue debt that is going to be borrowed which might not be in subAccount yet
    LibLYF01.accrueDebtPoolInterest(_vars.token0DebtPoolId, lyfDs);
    LibLYF01.accrueDebtPoolInterest(_vars.token1DebtPoolId, lyfDs);

    // prepare and send desired tokens to strategy for lp composition
    _prepareTokenToComposeLP(
      _vars.account,
      _vars.subAccount,
      _vars.token0,
      _vars.token0DebtPoolId,
      _input.lpToken,
      _lpConfig.strategy,
      _input.desiredToken0Amount,
      _input.token0ToBorrow,
      _input.token0AmountIn,
      lyfDs
    );
    _prepareTokenToComposeLP(
      _vars.account,
      _vars.subAccount,
      _vars.token1,
      _vars.token1DebtPoolId,
      _input.lpToken,
      _lpConfig.strategy,
      _input.desiredToken1Amount,
      _input.token1ToBorrow,
      _input.token1AmountIn,
      lyfDs
    );

    // compose lp
    _vars.lpReceived = IStrat(_lpConfig.strategy).composeLPToken(
      _vars.token0,
      _vars.token1,
      _input.lpToken,
      _input.desiredToken0Amount,
      _input.desiredToken1Amount,
      _input.minLpReceive
    );

    // deposit to masterChef
    LibLYF01.depositToMasterChef(_input.lpToken, _lpConfig.masterChef, _lpConfig.poolId, _vars.lpReceived);

    // add lp received from composition back to collateral
    LibLYF01.addCollat(_vars.subAccount, _input.lpToken, _vars.lpReceived, lyfDs);

    // health check
    // revert in case that lp collateralFactor is less than removed collateral's
    // or debt exceed borrowing power by borrowing too much
    if (!LibLYF01.isSubaccountHealthy(_vars.subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }

    emit LogAddFarmPosition(msg.sender, _input.subAccountId, _input.lpToken, _vars.lpReceived);
  }

  function _prepareTokenToComposeLP(
    address _account,
    address _subAccount,
    address _token,
    uint256 _debtPoolId,
    address _lpToken,
    address _lpStrat,
    uint256 _desiredAmount,
    uint256 _amountToBorrow,
    uint256 _suppliedAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    // borrow and validate min debt size
    if (_amountToBorrow != 0) {
      LibLYF01.borrow(_subAccount, _token, _lpToken, _amountToBorrow, lyfDs);
      LibLYF01.validateMinDebtSize(_subAccount, _debtPoolId, lyfDs);
    }

    PrepareTokenToComposeLPLocalVars memory _vars;

    // calculate collat amount to remove
    // already validate so its safe to use unchecked
    unchecked {
      _vars.amountToRemoveCollat = _desiredAmount - _amountToBorrow - _suppliedAmount;
    }

    if (_vars.amountToRemoveCollat != 0) {
      // remove normal collat first
      _vars.tokenAmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token, _vars.amountToRemoveCollat, lyfDs);

      // remove ib collat if normal collat removed not satisfy desired collat amount
      _vars.tokenAmountFromIbCollat = LibLYF01.removeIbCollateral(
        _account,
        _subAccount,
        _token,
        lyfDs.moneyMarket.getIbTokenFromToken(_token),
        _vars.amountToRemoveCollat - _vars.tokenAmountFromCollat,
        lyfDs
      );

      // revert if amount from collat removal less than desired collat amount
      unchecked {
        if (_vars.amountToRemoveCollat > _vars.tokenAmountFromCollat + _vars.tokenAmountFromIbCollat) {
          revert LYFFarmFacet_CollatNotEnough();
        }
      }
    }

    // send tokens to strat for lp composition
    // transfer user supplied part
    if (_suppliedAmount != 0) {
      IERC20(_token).safeTransferFrom(msg.sender, _lpStrat, _suppliedAmount);
    }
    // transfer borrowed + collat removed part

    unchecked {
      _vars.amountToStrat = _amountToBorrow + _vars.amountToRemoveCollat;
    }
    if (_vars.amountToStrat != 0) {
      IERC20(_token).safeTransfer(_lpStrat, _vars.amountToStrat);
    }
  }

  /// @notice Partially or fully close the position
  /// @param _subAccountId The index of subaccount
  /// @param _lpToken The LP token that associated with the position
  /// @param _lpShareAmount The share amount of LP to be removed
  /// @param _minAmount0Out The minimum expected return amount of token0 to the user
  /// @param _minAmount1Out The minimum expected return amount of token1 to the user
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

    _vars.debtPoolId0 = lyfDs.debtPoolIds[_vars.token0][_lpToken];
    _vars.debtPoolId1 = lyfDs.debtPoolIds[_vars.token1][_lpToken];

    LibLYF01.accrueDebtPoolInterest(_vars.debtPoolId0, lyfDs);
    LibLYF01.accrueDebtPoolInterest(_vars.debtPoolId1, lyfDs);

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
      _vars.debtPoolId0,
      _amount0ToRepay,
      lyfDs
    );
    (_vars.debtShare1ToRepay, _vars.debt1ToRepay) = _getActualDebtToRepay(
      _vars.subAccount,
      _vars.debtPoolId1,
      _amount1ToRepay,
      lyfDs
    );

    if (_vars.debtShare0ToRepay > 0) {
      _removeDebtAndValidate(_vars.subAccount, _vars.debtPoolId0, _vars.debtShare0ToRepay, _vars.debt0ToRepay, lyfDs);
    }
    if (_vars.debtShare1ToRepay > 0) {
      _removeDebtAndValidate(_vars.subAccount, _vars.debtPoolId1, _vars.debtShare1ToRepay, _vars.debt1ToRepay, lyfDs);
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

  /// @notice Repay the underlying debt of the position from the user's wallet
  ///@param _account The main account to repay to
  ///@param _subAccountId The index of subaccount
  ///@param _debtToken The token to repay
  ///@param _lpToken The associated lp for the position
  ///@param _debtShareToRepay The amount of share of debt to be repaied
  function repay(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _lpToken,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtPoolId = lyfDs.debtPoolIds[_debtToken][_lpToken];

    // must use storage because interest accrual increase totalValue
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];

    // only need to accrue debtPool that is being repaid
    LibLYF01.accrueDebtPoolInterest(_debtPoolId, lyfDs);

    // cap repay to max debt
    uint256 _actualShareToRepay = LibFullMath.min(
      _debtShareToRepay,
      lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId)
    );
    uint256 _actualRepayAmount = LibShareUtil.shareToValue(
      _actualShareToRepay,
      debtPoolInfo.totalValue,
      debtPoolInfo.totalShare
    );

    // transfer repay amount in, allow fee on transfer tokens
    uint256 _actualReceived = LibLYF01.unsafePullTokens(_debtToken, msg.sender, _actualRepayAmount);

    // repay by amount received if received less than expected aka. transfer has fee
    if (_actualReceived != _actualRepayAmount) {
      _actualRepayAmount = _actualReceived;
      _actualShareToRepay = LibShareUtil.valueToShare(
        _actualRepayAmount,
        debtPoolInfo.totalShare,
        debtPoolInfo.totalValue
      );
    }

    if (_actualRepayAmount > 0) {
      _removeDebtAndValidate(_subAccount, _debtPoolId, _actualShareToRepay, _actualRepayAmount, lyfDs);

      // update reserves of the token. This will impact the outstanding balance
      lyfDs.reserves[_debtToken] += _actualRepayAmount;
    }

    emit LogRepay(_account, _subAccountId, _debtToken, msg.sender, _actualRepayAmount);
  }

  /// @notice Compound the reward from Yield Farming
  /// @param _lpToken The lpToken that yield the reward token
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

  /// @notice Repay the underlying debt of the position from the subaccount's collateral
  ///@param _subAccountId The index of subaccount
  ///@param _token The token to repay
  ///@param _lpToken The associated lp for the position
  ///@param _debtShareToRepay The amount of share of debt to be repaied
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

    uint256 _debtPoolId = lyfDs.debtPoolIds[_token][_lpToken];
    uint256 _currentDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);

    // min(debtShareToRepay, currentDebtShare)
    uint256 _actualDebtShareToRemove = LibFullMath.min(_debtShareToRepay, _currentDebtShare);

    // prevent repay 0
    if (_actualDebtShareToRemove > 0) {
      LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
      // convert debtShare to debtAmount
      uint256 _actualDebtToRemove = LibShareUtil.shareToValue(
        _actualDebtShareToRemove,
        debtPoolInfo.totalValue,
        debtPoolInfo.totalShare
      );

      // if collat is not enough to repay debt, revert
      if (lyfDs.subAccountCollats[_subAccount].getAmount(_token) < _actualDebtToRemove) {
        revert LYFFarmFacet_CollatNotEnough();
      }

      // remove collat from subaccount
      LibLYF01.removeCollateral(_subAccount, _token, _actualDebtToRemove, lyfDs);

      _removeDebtAndValidate(_subAccount, _debtPoolId, _actualDebtShareToRemove, _actualDebtToRemove, lyfDs);

      emit LogRepayWithCollat(msg.sender, _subAccountId, _token, _debtPoolId, _actualDebtToRemove);
    }
  }

  function _removeDebtAndValidate(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _debtShareToRepay,
    uint256 _debtValueToRepay,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    LibLYF01.removeDebt(_subAccount, _debtPoolId, _debtShareToRepay, _debtValueToRepay, lyfDs);

    // validate after remove debt
    LibLYF01.validateMinDebtSize(_subAccount, _debtPoolId, lyfDs);
  }

  function accrueInterest(address _token, address _lpToken) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtPoolId = lyfDs.debtPoolIds[_token][_lpToken];
    LibLYF01.accrueDebtPoolInterest(_debtPoolId, lyfDs);
  }

  function _getActualDebtToRepay(
    address _subAccount,
    uint256 _debtPoolId,
    uint256 _desiredRepayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _actualShareToRepay, uint256 _actualToRepay) {
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];

    // debt share of sub account
    _actualShareToRepay = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);
    // Note: precision loss 1 wei when convert share back to value
    // debt value of sub account
    _actualToRepay = LibShareUtil.shareToValue(_actualShareToRepay, debtPoolInfo.totalValue, debtPoolInfo.totalShare);

    // if debt in sub account more than desired repay amount, then repay all of them
    if (_actualToRepay > _desiredRepayAmount) {
      _actualToRepay = _desiredRepayAmount;
      // convert desiredRepayAmount to share
      _actualShareToRepay = LibShareUtil.valueToShare(
        _desiredRepayAmount,
        debtPoolInfo.totalShare,
        debtPoolInfo.totalValue
      );
    }
  }
}
