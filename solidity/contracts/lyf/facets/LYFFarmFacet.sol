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
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract LYFFarmFacet is ILYFFarmFacet {
  using LibSafeToken for IERC20;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  struct ReducePositionLocalVars {
    address subAccount;
    address token0;
    address token1;
    uint256 debtShareId0;
    uint256 debtShareId1;
  }

  event LogRemoveDebt(
    address indexed _subAccount,
    uint256 indexed _debtShareId,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogAddFarmPosition(address indexed _subAccount, address indexed _lpToken, uint256 _lpAmount);

  event LogRepay(address indexed _subAccount, address _token, uint256 _actualRepayAmount);

  event LogRepayWithCollat(
    address indexed _user,
    uint256 indexed _subAccountId,
    address _token,
    uint256 _debtShareId,
    uint256 _actualRepayAmount
  );

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

    uint256 _token0DebtShareId = lyfDs.debtShareIds[_token0][_lpToken];
    uint256 _token1DebtShareId = lyfDs.debtShareIds[_token1][_lpToken];

    // accrue existing debt for healthcheck
    LibLYF01.accrueAllSubAccountDebtShares(_subAccount, lyfDs);

    // accrue new borrow debt
    LibLYF01.accrueInterest(_token0DebtShareId, lyfDs);
    LibLYF01.accrueInterest(_token1DebtShareId, lyfDs);

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
    emit LogAddFarmPosition(_subAccount, _lpToken, _lpReceived);
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

    LibLYF01.accrueAllSubAccountDebtShares(_subAccount, lyfDs);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    LibLYF01.accrueInterest(lyfDs.debtShareIds[_token0][_lpToken], lyfDs);
    LibLYF01.accrueInterest(lyfDs.debtShareIds[_token1][_lpToken], lyfDs);

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
    emit LogAddFarmPosition(_subAccount, _lpToken, _lpReceived);
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

    LibLYF01.accrueInterest(lyfDs.debtShareIds[_vars.token0][_lpToken], lyfDs);
    LibLYF01.accrueInterest(lyfDs.debtShareIds[_vars.token1][_lpToken], lyfDs);

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

    // 3. Remove debt by repay amount
    _repayDebtByAmount(_vars.subAccount, _vars.debtShareId0, _token0Return - _amount0Out, lyfDs);
    _repayDebtByAmount(_vars.subAccount, _vars.debtShareId1, _token1Return - _amount1Out, lyfDs);

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

    LibLYF01.accrueInterest(_debtShareId, lyfDs);

    // remove debt as much as possible
    (, uint256 _actualRepayAmount) = _repayDebtByShare(_subAccount, _debtShareId, _debtShareToRepay, lyfDs);

    // transfer only amount to repay
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);
    // update reserves of the token. This will impact the outstanding balance
    lyfDs.reserves[_token] += _actualRepayAmount;

    emit LogRepay(_subAccount, _token, _actualRepayAmount);
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

    LibLYF01.reinvest(_lpToken, 0, lyfDs.lpConfigs[_lpToken], lyfDs);
  }

  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _debtToRepay
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);
    LibLYF01.accrueAllSubAccountDebtShares(_subAccount, lyfDs);

    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    (, uint256 _debtAmount) = LibLYF01.getDebt(_subAccount, _debtShareId, lyfDs);

    // repay maxmimum debt
    _debtToRepay = _debtToRepay > _debtAmount ? _debtAmount : _debtToRepay;

    if (_debtToRepay != 0) {
      // remove collat as much as possible
      uint256 _removedCollat = LibLYF01.removeCollateral(_subAccount, _token, _debtToRepay, lyfDs);

      // remove debt as much as possible
      (, uint256 _actualRepayAmount) = _repayDebtByAmount(_subAccount, _debtShareId, _removedCollat, lyfDs);

      emit LogRepayWithCollat(msg.sender, _subAccountId, _token, _debtShareId, _actualRepayAmount);
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
      IMoneyMarket(lyfDs.moneyMarket).getIbTokenFromToken(_token),
      _desireTokenAmount - _tokenAmountFromCollat,
      lyfDs
    );
    LibLYF01.borrowFromMoneyMarket(
      _subAccount,
      _token,
      _lpToken,
      _desireTokenAmount - _tokenAmountFromCollat - _tokenAmountFromIbCollat,
      lyfDs
    );
  }

  function _repayDebtByAmount(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _repayAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _repaidShare, uint256 _repaidAmount) {
    (_repaidShare, _repaidAmount) = LibLYF01.geSubAccountMaxPossibleDebtsByValue(
      _subAccount,
      _debtShareId,
      _repayAmount,
      lyfDs
    );
    LibLYF01.removeDebts(_subAccount, _debtShareId, _repaidShare, _repaidAmount, lyfDs);

    // validate after remove debt
    LibLYF01.validateMinDebtSize(_subAccount, _debtShareId, lyfDs);
  }

  function _repayDebtByShare(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _repayShare,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _repaidShare, uint256 _repaidAmount) {
    (_repaidShare, _repaidAmount) = LibLYF01.geSubAccountMaxPossibleDebtsByShare(
      _subAccount,
      _debtShareId,
      _repayShare,
      lyfDs
    );
    LibLYF01.removeDebts(_subAccount, _debtShareId, _repaidShare, _repaidAmount, lyfDs);

    // validate after remove debt
    LibLYF01.validateMinDebtSize(_subAccount, _debtShareId, lyfDs);
  }

  function accrueInterest(address _token, address _lpToken) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    LibLYF01.accrueInterest(_debtShareId, lyfDs);
  }
}
