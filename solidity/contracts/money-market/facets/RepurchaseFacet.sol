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
    address _repayToken,
    address _collatToken,
    uint256 _repayAmount
  ) external returns (uint256 _collatAmountOut) {
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    uint256 _borrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
    uint256 _borrowedValue = LibMoneyMarket01.getTotalBorrowedUSDValue(_subAccount, moneyMarketDs);

    if (_borrowingPower > _borrowedValue) {
      revert RepurchaseFacet_Healthy();
    }

    (uint256 _actualRepayAmount, uint256 _actualRepayShare) = _getActualRepayDebt(
      _subAccount,
      _repayToken,
      _repayAmount,
      moneyMarketDs
    );

    uint256 _repayTokenPrice = LibMoneyMarket01.getPrice(_repayToken, moneyMarketDs);
    // todo: handle token decimals
    uint256 _repayInUSD = (_actualRepayAmount * _repayTokenPrice) / 1e18;
    // todo: tbd
    if (_repayInUSD * 2 > _borrowedValue) {
      revert RepurchaseFacet_RepayDebtValueTooHigh();
    }

    // calculate collateral amount that repurchaser will receive
    _collatAmountOut = _getCollatAmountOut(_subAccount, _collatToken, _repayInUSD, moneyMarketDs);

    _updateDebts(_subAccount, _repayToken, _actualRepayAmount, _actualRepayShare, moneyMarketDs);
    _updateCollats(_subAccount, _collatToken, _collatAmountOut, moneyMarketDs);

    ERC20(_repayToken).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);

    emit LogRepurchase(msg.sender, _repayToken, _collatToken, _repayAmount, _collatAmountOut);
  }

  function _getActualRepayDebt(
    address _subAccount,
    address _repayToken,
    uint256 _repayAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
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
    address _subAccount,
    address _collatToken,
    uint256 _repayInUSD,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _collatTokenAmountOut) {
    uint256 _collatTokenPrice = LibMoneyMarket01.getPrice(_collatToken, moneyMarketDs);
    uint256 _rewardInUSD = (_repayInUSD * REPURCHASE_BPS) / 1e4;
    _collatTokenAmountOut = ((_repayInUSD + _rewardInUSD) * 1e18) / _collatTokenPrice;

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
