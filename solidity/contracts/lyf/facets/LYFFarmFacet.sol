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

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
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

    uint256 _token0DebtPoolId = lyfDs.debtPoolIds[_token0][_lpToken];
    uint256 _token1DebtPoolId = lyfDs.debtPoolIds[_token1][_lpToken];

    // accrue existing debt for healthcheck
    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    // accrue new borrow debt
    LibLYF01.accrueDebtPoolInterest(_token0DebtPoolId, lyfDs);
    LibLYF01.accrueDebtPoolInterest(_token1DebtPoolId, lyfDs);

    // 1. get token from collat (underlying and ib if possible), borrow if not enough
    _removeCollatWithIbAndBorrow(_subAccount, _token0, _lpToken, _desireToken0Amount, lyfDs);
    _removeCollatWithIbAndBorrow(_subAccount, _token1, _lpToken, _desireToken1Amount, lyfDs);

    // 2. Check min debt size
    LibLYF01.validateMinDebtSize(_subAccount, _token0DebtPoolId, lyfDs);
    LibLYF01.validateMinDebtSize(_subAccount, _token1DebtPoolId, lyfDs);

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

    LibLYF01.accrueDebtPoolInterest(lyfDs.debtPoolIds[_token0][_lpToken], lyfDs);
    LibLYF01.accrueDebtPoolInterest(lyfDs.debtPoolIds[_token1][_lpToken], lyfDs);

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
