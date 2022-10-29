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

// TODO: remove
import { console } from "../../../tests/utils/console.sol";

contract CollateralFacet is ICollateralFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogAddCollateral(
    address indexed _subAccount,
    address indexed _token,
    uint256 _amount
  );

  event LogRemoveCollateral(
    address indexed _subAccount,
    address indexed _token,
    uint256 _amount
  );

  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _validate(_token, _amount, moneyMarketDs);

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

    emit LogAddCollateral(_subAccount, _token, _amount);
  }

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      msg.sender,
      _subAccountId
    );

    LibDoublyLinkedList.List storage _subAccountCollatList = moneyMarketDs
      .subAccountCollats[_subAccount];

    uint256 _collateralAmount = _subAccountCollatList.getAmount(_token);

    // Question: This check can be removed since if _removeAmount > _collateralAmount it will revert by underflow
    if (_removeAmount > _collateralAmount) {
      revert CollateralFacet_TooManyCollateralRemoved();
    }

    _subAccountCollatList.updateOrRemove(
      _token,
      _collateralAmount - _removeAmount
    );

    uint256 _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(
      _subAccount,
      moneyMarketDs
    );

    (uint256 _totalUsedBorrowedPower, ) = LibMoneyMarket01
      .getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);

    if (_totalBorrowingPower < _totalUsedBorrowedPower) {
      revert CollateralFacet_BorrowingPowerTooLow();
    }

    ERC20(_token).transfer(msg.sender, _removeAmount);

    emit LogRemoveCollateral(_subAccount, _token, _removeAmount);
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

  function _validate(
    address _token,
    uint256 _collateralAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    if (
      moneyMarketDs.tokenConfigs[_token].tier !=
      LibMoneyMarket01.AssetTier.COLLATERAL
    ) {
      revert CollateralFacet_InvalidAssetTier();
    }

    if (_collateralAmount > moneyMarketDs.tokenConfigs[_token].maxCollateral) {
      revert CollateralFacet_ExceedCollateralLimit();
    }
  }
}
