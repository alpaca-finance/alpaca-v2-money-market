// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

// interfaces
import { ICollateralFacet } from "../interfaces/ICollateralFacet.sol";

contract CollateralFacet is ICollateralFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (
      moneyMarketDs.assetTiers[_token] != LibMoneyMarket01.AssetTier.COLLATERAL
    ) {
      revert CollateralFacet_InvalidAssetTier();
    }

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    LibDoublyLinkedList.List storage collats = moneyMarketDs.subAccountCollats[
      _subAccount
    ];
    if (
      collats.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY
    ) {
      collats.init();
    }

    uint256 _newAmount = collats.getAmount(_token) + _amount;
    collats.addOrUpdate(_token, _newAmount);

    moneyMarketDs.collats[_token] += _amount;
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
  }

  function getCollaterals(address _account, uint256 _subAccountId)
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

    LibDoublyLinkedList.List storage collats = moneyMarketDs.subAccountCollats[
      _subAccount
    ];

    return collats.getAll();
  }
}
