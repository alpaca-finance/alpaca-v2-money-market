// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";

// interfaces
import { IBorrowFacet } from "../interfaces/IBorrowFacet.sol";

contract BorrowFacet is IBorrowFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function borrow(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    if (_ibToken == address(0)) {
      revert BorrowFacet_InvalidToken(_token);
    }

    _checkBorrowingPower(_subAccount, _token, _amount, moneyMarketDs);

    _checkAvailableToken(_token, _amount, moneyMarketDs);

    LibDoublyLinkedList.List storage debtShare = moneyMarketDs
      .subAccountDebtShares[_subAccount];

    if (
      debtShare.getNextOf(LibDoublyLinkedList.START) ==
      LibDoublyLinkedList.EMPTY
    ) {
      debtShare.init();
    }

    uint256 _totalSupply = moneyMarketDs.debtShares[_token];
    uint256 _totalValue = moneyMarketDs.debtValues[_token];

    uint256 _shareToAdd = LibShareUtil.valueToShare(
      _totalSupply,
      _amount,
      _totalValue
    );

    moneyMarketDs.debtShares[_token] += _shareToAdd;
    moneyMarketDs.debtValues[_token] += _amount;

    uint256 _newAmount = debtShare.getAmount(_token) + _amount;
    // update user's debtshare
    debtShare.addOrUpdate(_token, _newAmount);

    ERC20(_token).safeTransfer(_account, _amount);
  }

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    LibDoublyLinkedList.List storage debtShares = moneyMarketDs
      .subAccountDebtShares[_subAccount];

    return debtShares.getAll();
  }

  // TODO: handle token decimal when calculate value
  function _checkBorrowingPower(
    address _subAccount,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // TODO: get tokenPrice from oracle
    uint256 _tokenPrice = 1e18;

    uint256 _borrowingUSDValue = LibFullMath.mulDiv(_amount, _tokenPrice, 1e18);
    uint256 _totalBorrowingPowerUSDValue = 0;
    uint256 _totalBorrowedUSDValue = 0;

    LibDoublyLinkedList.Node[] memory _collats = moneyMarketDs
      .subAccountCollats[_subAccount]
      .getAll();

    uint256 _collatsLength = _collats.length;

    for (uint256 _i = 0; _i < _collatsLength; ) {
      // TODO: get tokenPrice from oracle
      _tokenPrice = 1e18;
      // TODO: add collateral factor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _collats[_i].amount,
        _tokenPrice,
        1e18
      );

      unchecked {
        _i++;
      }
    }

    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs
      .subAccountDebtShares[_subAccount]
      .getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      // TODO: get tokenPrice from oracle
      _tokenPrice = 1e18;
      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        moneyMarketDs.debtShares[_borrowed[_i].token],
        _borrowed[_i].amount,
        moneyMarketDs.debtValues[_borrowed[_i].token]
      );

      // TODO: add borrow factor
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        _borrowedAmount,
        _tokenPrice,
        1e18
      );

      unchecked {
        _i++;
      }
    }

    if (
      _totalBorrowingPowerUSDValue < _totalBorrowedUSDValue + _borrowingUSDValue
    ) {
      revert BorrowFacet_BorrowingValueTooHigh(
        _totalBorrowingPowerUSDValue,
        _totalBorrowedUSDValue,
        _borrowingUSDValue
      );
    }
  }

  function _checkAvailableToken(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) -
      moneyMarketDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
      revert BorrowFacet_NotEnoughToken(_borrowAmount);
    }
  }
}
