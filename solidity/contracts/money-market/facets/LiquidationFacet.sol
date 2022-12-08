// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { ILiquidationFacet } from "../interfaces/ILiquidationFacet.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";
import { ILiquidationStrategy } from "../interfaces/ILiquidationStrategy.sol";
import { ILendFacet } from "../interfaces/ILendFacet.sol";

contract LiquidationFacet is ILiquidationFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeERC20 for ERC20;

  struct InternalLiquidationCallParams {
    address liquidationStrat;
    address subAccount;
    address repayToken;
    address collatToken;
    uint256 repayAmount;
  }

  uint256 constant REPURCHASE_REWARD_BPS = 100;
  uint256 constant REPURCHASE_FEE_BPS = 100;
  uint256 constant LIQUIDATION_FEE_BPS = 100;

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) external nonReentrant returns (uint256 _collatAmountOut) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.repurchasersOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    // avoid stack too deep
    uint256 _borrowedValue;
    {
      uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
      _borrowedValue = LibMoneyMarket01.getTotalBorrowedUSDValue(_subAccount, moneyMarketDs);

      if (_borrowingPower > _borrowedValue) {
        revert LiquidationFacet_Healthy();
      }
    }

    uint256 _actualRepayAmountWithFee = _getActualRepayAmountWithFee(
      _subAccount,
      _repayToken,
      _repayAmount,
      moneyMarketDs
    );
    uint256 _repurchaseFee = (_actualRepayAmountWithFee * REPURCHASE_FEE_BPS) / 10000;

    (uint256 _repayTokenPrice, ) = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);
    LibMoneyMarket01.TokenConfig memory _repayTokenConfig = moneyMarketDs.tokenConfigs[_repayToken];

    uint256 _repayInUSDWithFee = (_actualRepayAmountWithFee *
      _repayTokenConfig.to18ConversionFactor *
      _repayTokenPrice) / 1e18;
    // todo: tbd
    if (_repayInUSDWithFee * 2 > _borrowedValue) {
      revert LiquidationFacet_RepayDebtValueTooHigh();
    }

    // calculate collateral amount that repurchaser will receive
    _collatAmountOut = _getCollatAmountOut(
      _subAccount,
      _collatToken,
      _repayInUSDWithFee,
      REPURCHASE_REWARD_BPS,
      moneyMarketDs
    );

    _reduceDebt(_subAccount, _repayToken, _actualRepayAmountWithFee - _repurchaseFee, moneyMarketDs);
    _reduceCollateral(_subAccount, _collatToken, _collatAmountOut, moneyMarketDs);

    ERC20(_repayToken).safeTransferFrom(msg.sender, address(this), _actualRepayAmountWithFee);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);
    ERC20(_repayToken).safeTransfer(moneyMarketDs.treasury, _repurchaseFee);

    emit LogRepurchase(
      msg.sender,
      _repayToken,
      _collatToken,
      _actualRepayAmountWithFee,
      _collatAmountOut,
      _repurchaseFee
    );
  }

  function liquidationCall(
    address _liquidationStrat,
    address _account,
    uint256 _subAccountId,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.liquidationStratOk[_liquidationStrat] || !moneyMarketDs.liquidationCallersOk[msg.sender]) {
      revert LiquidationFacet_Unauthorized();
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    // 1. check if position is underwater and can be liquidated
    {
      uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
      (uint256 _usedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);
      if ((_borrowingPower * 10000) > _usedBorrowingPower * 9000) {
        revert LiquidationFacet_Healthy();
      }
    }

    InternalLiquidationCallParams memory _params = InternalLiquidationCallParams({
      liquidationStrat: _liquidationStrat,
      subAccount: _subAccount,
      repayToken: _repayToken,
      collatToken: _collatToken,
      repayAmount: _repayAmount
    });

    address _collatUnderlyingToken = moneyMarketDs.ibTokenToTokens[_collatToken];
    // handle liqudiate ib as collat
    if (_collatUnderlyingToken != address(0)) {
      _ibLiquidationCall(_params, _collatUnderlyingToken, moneyMarketDs);
    } else {
      _liquidationCall(_params, moneyMarketDs);
    }
  }

  function _liquidationCall(
    InternalLiquidationCallParams memory params,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // 2. send all collats under subaccount to strategy
    uint256 _collatAmountBefore = ERC20(params.collatToken).balanceOf(address(this));
    uint256 _repayAmountBefore = ERC20(params.repayToken).balanceOf(address(this));

    ERC20(params.collatToken).safeTransfer(
      params.liquidationStrat,
      moneyMarketDs.subAccountCollats[params.subAccount].getAmount(params.collatToken)
    );

    // 3. call executeLiquidation on strategy
    uint256 _actualRepayAmount = _getActualRepayAmount(
      params.subAccount,
      params.repayToken,
      params.repayAmount,
      moneyMarketDs
    );
    uint256 _feeToTreasury = (_actualRepayAmount * LIQUIDATION_FEE_BPS) / 10000;

    ILiquidationStrategy(params.liquidationStrat).executeLiquidation(
      params.collatToken,
      params.repayToken,
      _actualRepayAmount + _feeToTreasury,
      address(this)
    );

    // 4. check repaid amount, take fees, and update states
    uint256 _repayAmountFromLiquidation = ERC20(params.repayToken).balanceOf(address(this)) - _repayAmountBefore;
    uint256 _repaidAmount = _repayAmountFromLiquidation - _feeToTreasury;
    uint256 _collatSold = _collatAmountBefore - ERC20(params.collatToken).balanceOf(address(this));

    ERC20(params.repayToken).safeTransfer(moneyMarketDs.treasury, _feeToTreasury);

    // give priority to fee
    _reduceDebt(params.subAccount, params.repayToken, _repaidAmount, moneyMarketDs);
    _reduceCollateral(params.subAccount, params.collatToken, _collatSold, moneyMarketDs);

    emit LogLiquidate(
      msg.sender,
      params.liquidationStrat,
      params.repayToken,
      params.collatToken,
      _repaidAmount,
      _collatSold,
      _feeToTreasury
    );
  }

  function _ibLiquidationCall(
    InternalLiquidationCallParams memory params,
    address _collatUnderlyingToken,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // 2. convert collat amount under subaccount to underlying amount and send underlying to strategy
    uint256 _underlyingAmountBefore = ERC20(_collatUnderlyingToken).balanceOf(address(this));
    uint256 _repayAmountBefore = ERC20(params.repayToken).balanceOf(address(this));

    // if mm has no actual token left, withdraw will fail anyway
    ERC20(_collatUnderlyingToken).safeTransfer(
      params.liquidationStrat,
      _shareToValue(
        params.collatToken,
        moneyMarketDs.subAccountCollats[params.subAccount].getAmount(params.collatToken),
        _underlyingAmountBefore
      )
    );

    // 3. call executeLiquidation on strategy to liquidate underlying token
    uint256 _actualRepayAmount = _getActualRepayAmount(
      params.subAccount,
      params.repayToken,
      params.repayAmount,
      moneyMarketDs
    );
    uint256 _feeToTreasury = (_actualRepayAmount * LIQUIDATION_FEE_BPS) / 10000;

    ILiquidationStrategy(params.liquidationStrat).executeLiquidation(
      _collatUnderlyingToken,
      params.repayToken,
      _actualRepayAmount + _feeToTreasury,
      address(this)
    );

    // 4. check repaid amount, take fees, and update states
    uint256 _repayAmountFromLiquidation = ERC20(params.repayToken).balanceOf(address(this)) - _repayAmountBefore;
    uint256 _repaidAmount = _repayAmountFromLiquidation - _feeToTreasury;
    uint256 _underlyingSold = _underlyingAmountBefore - ERC20(_collatUnderlyingToken).balanceOf(address(this));
    uint256 _collatSold = _valueToShare(params.collatToken, _underlyingSold, _underlyingAmountBefore);

    ERC20(params.repayToken).safeTransfer(moneyMarketDs.treasury, _feeToTreasury);

    LibMoneyMarket01.withdraw(params.collatToken, _collatSold, address(this), moneyMarketDs);

    // give priority to fee
    _reduceDebt(params.subAccount, params.repayToken, _repaidAmount, moneyMarketDs);
    _reduceCollateral(params.subAccount, params.collatToken, _collatSold, moneyMarketDs);

    emit LogLiquidateIb(
      msg.sender,
      params.liquidationStrat,
      params.repayToken,
      params.collatToken,
      _repaidAmount,
      _collatSold,
      _underlyingSold,
      _feeToTreasury
    );
  }

  function _valueToShare(
    address _ibToken,
    uint256 _value,
    uint256 _totalToken
  ) internal view returns (uint256 _shareValue) {
    uint256 _totalSupply = ERC20(_ibToken).totalSupply();

    _shareValue = LibShareUtil.valueToShare(_value, _totalSupply, _totalToken);
  }

  function _shareToValue(
    address _ibToken,
    uint256 _shareAmount,
    uint256 _totalToken
  ) internal view returns (uint256 _underlyingAmount) {
    uint256 _totalSupply = ERC20(_ibToken).totalSupply();

    _underlyingAmount = LibShareUtil.shareToValue(_shareAmount, _totalToken, _totalSupply);
  }

  /// @dev min(repayAmount, debtValue)
  function _getActualRepayAmount(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _actualRepayAmount) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    // for ib debtValue is in ib shares not in underlying
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_repayToken],
      moneyMarketDs.debtShares[_repayToken]
    );

    _actualRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
  }

  /// @dev min(repayAmount, debtValue + fee)
  /// get actual repay amount for repurchase
  function _getActualRepayAmountWithFee(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _actualRepayAmount) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);

    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_repayToken],
      moneyMarketDs.debtShares[_repayToken]
    );

    // let _debtValue is value after reduced repurchse fee
    uint256 _estimatedFee = (_debtValue * REPURCHASE_FEE_BPS) / (LibMoneyMarket01.MAX_BPS - REPURCHASE_FEE_BPS);
    uint256 _debtValueWithFee = _debtValue + _estimatedFee;

    _actualRepayAmount = _repayAmount > _debtValueWithFee ? _debtValueWithFee : _repayAmount;
  }

  /// @return _collatTokenAmountOut collateral amount after include rewardBps
  function _getCollatAmountOut(
    address _subAccount,
    address _collatToken,
    uint256 _collatValueInUSD,
    uint256 _rewardBps,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _collatTokenAmountOut) {
    address _actualToken = moneyMarketDs.ibTokenToTokens[_collatToken];

    uint256 _collatTokenPrice;
    {
      // _collatToken is ibToken
      if (_actualToken != address(0)) {
        (_collatTokenPrice, ) = LibMoneyMarket01.getIbPriceUSD(_collatToken, _actualToken, moneyMarketDs);
      } else {
        (_collatTokenPrice, ) = LibMoneyMarket01.getPriceUSD(_collatToken, moneyMarketDs);
      }
    }

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_collatToken];

    // avoid stack too deep
    {
      uint256 _rewardInUSD = (_collatValueInUSD * _rewardBps) / 10000;
      _collatTokenAmountOut =
        ((_collatValueInUSD + _rewardInUSD) * 1e18) /
        (_collatTokenPrice * _tokenConfig.to18ConversionFactor);
    }

    uint256 _collatTokenTotalAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatTokenAmountOut > _collatTokenTotalAmount) {
      revert LiquidationFacet_InsufficientAmount();
    }
  }

  function _reduceDebt(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    uint256 _repayShare = LibShareUtil.valueToShare(
      _repayAmount,
      moneyMarketDs.debtShares[_repayToken],
      moneyMarketDs.debtValues[_repayToken]
    );
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _debtShare - _repayShare);
    moneyMarketDs.debtShares[_repayToken] -= _repayShare;
    moneyMarketDs.debtValues[_repayToken] -= _repayAmount;
  }

  function _reduceCollateral(
    address _subAccount,
    address _collatToken,
    uint256 _amountOut,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _collatTokenAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);
    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_collatToken, _collatTokenAmount - _amountOut);
    moneyMarketDs.collats[_collatToken] -= _amountOut;
  }
}
