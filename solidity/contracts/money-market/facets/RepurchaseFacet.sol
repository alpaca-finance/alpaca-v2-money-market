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

  error RepurchaseFacet_BorrowingPowerIsCovered();
  error RepurchaseFacet_RepayDebtValueTooHigh();
  error RepurchaseFacet_InsufficientAmount();

  function repurchase(
    address _subAccount,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) external returns (uint256 _amountOut) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    uint256 _borrowedValue = LibMoneyMarket01.getTotalBorrowedValue(_subAccount, moneyMarketDs);

    if (_borrowingPower > _borrowedValue) {
      revert RepurchaseFacet_BorrowingPowerIsCovered();
    }

    (uint256 _actualRepayAmount, uint256 _actualRepayValue) = _getActualRepay(
      moneyMarketDs,
      _subAccount,
      _repayToken,
      _repayAmount
    );

    // todo: make it as constant
    if (_actualRepayValue > (_borrowedValue * 50) / 100) {
      revert RepurchaseFacet_RepayDebtValueTooHigh();
    }

    // todo: get tokenPrice from oracle
    uint256 _collatTokenPrice = 1e18;
    _amountOut = _actualRepayValue / _collatTokenPrice;

    _validateCollat(moneyMarketDs, _subAccount, _collatToken, _amountOut);

    _updateState(
      moneyMarketDs,
      _subAccount,
      _repayToken,
      _collatToken,
      _actualRepayAmount,
      _actualRepayValue,
      _amountOut
    );

    ERC20(_repayToken).safeTransferFrom(address(this), msg.sender, _amountOut);
    ERC20(_collatToken).safeTransfer(msg.sender, _amountOut);
  }

  function _getActualRepay(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualRepayValue) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_repayToken],
      moneyMarketDs.debtShares[_repayToken]
    );

    _actualRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
    _actualRepayValue = LibShareUtil.shareToValue(
      _actualRepayAmount,
      moneyMarketDs.debtValues[_repayToken],
      moneyMarketDs.debtShares[_repayToken]
    );
  }

  function _validateCollat(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _collatToken,
    uint256 _removeCollatAmount
  ) internal view {
    uint256 _collatTokenAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (
      _removeCollatAmount > _collatTokenAmount || _removeCollatAmount > ERC20(_collatToken).balanceOf(address(this))
    ) {
      revert RepurchaseFacet_InsufficientAmount();
    }
  }

  function _updateState(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _repayToken,
    address _collatToken,
    uint256 _actualRepayAmount,
    uint256 _actualRepayValue,
    uint256 _amountOut
  ) internal {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    // update state
    // remove debt
    // update user debtShare
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _debtShare - _actualRepayAmount);
    moneyMarketDs.debtShares[_repayToken] -= _actualRepayAmount;
    moneyMarketDs.debtValues[_repayToken] -= _actualRepayValue;

    // remove collat
    uint256 _collatTokenAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);
    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_collatToken, _collatTokenAmount - _amountOut);
    moneyMarketDs.collats[_collatToken] -= _amountOut;
  }
}
