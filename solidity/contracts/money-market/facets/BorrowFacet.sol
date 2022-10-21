// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

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

    if (_ibToken == address(0)) {
      revert BorrowFacet_InvalidToken(_token);
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    LibDoublyLinkedList.List storage debtShare = moneyMarketDs
      .subAccountDebtShares[_subAccount];

    if (
      debtShare.getNextOf(LibDoublyLinkedList.START) ==
      LibDoublyLinkedList.EMPTY
    ) {
      debtShare.init();
    }

    uint256 _newAmount = debtShare.getAmount(_token) + _amount;
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
}
