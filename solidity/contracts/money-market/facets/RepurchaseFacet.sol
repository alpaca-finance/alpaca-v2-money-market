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

import { console } from "../../../tests/utils/console.sol";

contract RepurchaseFacet is IRepurchaseFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeERC20 for ERC20;

  uint8 constant REPURCHASE_BPS = 100;

  function repurchase(
    address _subAccount,
    address _debtToken,
    address _collatToken,
    uint256 _repayAmount
  ) external returns (uint256 _collatAmountOut) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    uint256 _borrowedValue = LibMoneyMarket01.getTotalBorrowedValue(_subAccount, moneyMarketDs);

    if (_borrowingPower > _borrowedValue) {
      revert RepurchaseFacet_Healthy();
    }

    (uint256 _actualRepayAmount, uint256 _actualRepayShare) = _getActualRepayDebt(
      moneyMarketDs,
      _subAccount,
      _debtToken,
      _repayAmount
    );

    // todo: make it as constant
    if (_actualRepayAmount > (_borrowedValue * 50) / 100) {
      revert RepurchaseFacet_RepayDebtValueTooHigh();
    }

    _collatAmountOut = _getCollatAmountOut(moneyMarketDs, _subAccount, _debtToken, _collatToken, _repayAmount);

    _updateState(
      moneyMarketDs,
      _subAccount,
      _debtToken,
      _collatToken,
      _actualRepayAmount,
      _actualRepayShare,
      _collatAmountOut
    );

    ERC20(_debtToken).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);

    emit LogRepurchase(msg.sender, _debtToken, _collatToken, _repayAmount, _collatAmountOut);
  }

  function _getActualRepayDebt(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount
  ) internal view returns (uint256 _actualRepayAmount, uint256 _actualRepayShare) {
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_repayToken],
      moneyMarketDs.debtShares[_repayToken]
    );

    _actualRepayAmount = _repayAmount > _debtValue ? _debtValue : _repayAmount;
    _actualRepayShare = LibShareUtil.valueToShare(
      moneyMarketDs.debtShares[_repayToken],
      _actualRepayAmount,
      moneyMarketDs.debtValues[_repayToken]
    );
  }

  function _getCollatAmountOut(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) internal view returns (uint256 _collatTokenAmountOut) {
    uint256 _repayTokenPrice = LibMoneyMarket01.getPrice(_repayToken, moneyMarketDs);
    uint256 _collatTokenPrice = LibMoneyMarket01.getPrice(_collatToken, moneyMarketDs);
    uint256 _repayInUSD = _repayAmount * _repayTokenPrice;
    uint256 _rewardInUSD = (_repayInUSD * REPURCHASE_BPS) / 1e4;
    _collatTokenAmountOut = (_repayInUSD + _rewardInUSD) / _collatTokenPrice;

    uint256 _collatTokenTotalAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatTokenAmountOut > _collatTokenTotalAmount) {
      revert RepurchaseFacet_InsufficientAmount();
    }
  }

  function _updateState(
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs,
    address _subAccount,
    address _repayToken,
    address _collatToken,
    uint256 _actualRepayAmount,
    uint256 _actualRepayShare,
    uint256 _amountOut
  ) internal {
    // remove debt
    uint256 _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_repayToken);
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_repayToken, _debtShare - _actualRepayShare);
    moneyMarketDs.debtShares[_repayToken] -= _actualRepayShare;
    moneyMarketDs.debtValues[_repayToken] -= _actualRepayAmount;

    // remove collat
    uint256 _collatTokenAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_collatToken);
    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_collatToken, _collatTokenAmount - _amountOut);
    moneyMarketDs.collats[_collatToken] -= _amountOut;
  }
}
