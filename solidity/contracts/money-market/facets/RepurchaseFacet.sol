// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IRepurchaseFacet } from "../interfaces/IRepurchaseFacet.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";

contract RepurchaseFacet is IRepurchaseFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeERC20 for ERC20;

  uint8 constant REPURCHASE_BPS = 100;

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    uint256 _repayAmount
  ) external returns (uint256 _collatAmountOut) {
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    uint256 _borrowedValue = LibMoneyMarket01.getTotalBorrowedValue(_subAccount, moneyMarketDs);

    if (_borrowingPower > _borrowedValue) {
      revert RepurchaseFacet_Healthy();
    }

    (uint256 _actualRepayAmount, uint256 _actualRepayShare) = _getActualRepayDebt(
      _subAccount,
      _debtToken,
      _repayAmount,
      moneyMarketDs
    );

    // todo: make it as constant
    if (_actualRepayAmount > (_borrowedValue * 50) / 100) {
      revert RepurchaseFacet_RepayDebtValueTooHigh();
    }

    // calculate collateral amount that repurchaser will receive
    _collatAmountOut = _getCollatAmountOut(_subAccount, _debtToken, _collatToken, _actualRepayAmount, moneyMarketDs);

    _updateDebts(_subAccount, _debtToken, _actualRepayAmount, _actualRepayShare, moneyMarketDs);
    _updateCollats(_subAccount, _collatToken, _collatAmountOut, moneyMarketDs);

    ERC20(_debtToken).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);

    emit LogRepurchase(msg.sender, _debtToken, _collatToken, _repayAmount, _collatAmountOut);
  }

  function _getActualRepayDebt(
    address _subAccount,
    address _debtToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualRepayShare) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_debtToken);
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_debtToken],
      moneyMarketDs.debtShares[_debtToken]
    );

    _actualRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
    _actualRepayShare = LibShareUtil.valueToShare(
      moneyMarketDs.debtShares[_debtToken],
      _actualRepayAmount,
      moneyMarketDs.debtValues[_debtToken]
    );
  }

  function _getCollatAmountOut(
    address _subAccount,
    address _debtToken,
    address _collatToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _collatTokenAmountOut) {
    uint256 _debtTokenPrice = LibMoneyMarket01.getPrice(_debtToken, moneyMarketDs);
    uint256 _collatTokenPrice = LibMoneyMarket01.getPrice(_collatToken, moneyMarketDs);
    uint256 _repayInUSD = _repayAmount * _debtTokenPrice;
    uint256 _rewardInUSD = (_repayInUSD * REPURCHASE_BPS) / 1e4;
    _collatTokenAmountOut = (_repayInUSD + _rewardInUSD) / _collatTokenPrice;

    uint256 _collatTokenTotalAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatTokenAmountOut > _collatTokenTotalAmount) {
      revert RepurchaseFacet_InsufficientAmount();
    }
  }

  function _updateDebts(
    address _subAccount,
    address _repayToken,
    uint256 _actualRepayAmount,
    uint256 _actualRepayShare,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _debtShare - _actualRepayShare);
    moneyMarketDs.debtShares[_repayToken] -= _actualRepayShare;
    moneyMarketDs.debtValues[_repayToken] -= _actualRepayAmount;
  }

  function _updateCollats(
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
