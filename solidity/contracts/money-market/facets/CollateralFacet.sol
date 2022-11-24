// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { ICollateralFacet } from "../interfaces/ICollateralFacet.sol";

contract CollateralFacet is ICollateralFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogAddCollateral(address indexed _subAccount, address indexed _token, uint256 _amount);

  event LogRemoveCollateral(address indexed _subAccount, address indexed _token, uint256 _amount);

  event LogTransferCollateral(
    address indexed _fromSubAccount,
    address indexed _toSubAccount,
    address indexed _token,
    uint256 _amount
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _validateAddCollateral(_token, _amount, moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountCollateralList = moneyMarketDs.subAccountCollats[_subAccount];
    if (subAccountCollateralList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      subAccountCollateralList.init();
    }

    uint256 _newAmount = subAccountCollateralList.getAmount(_token) + _amount;
    subAccountCollateralList.addOrUpdate(_token, _newAmount);

    moneyMarketDs.collats[_token] += _amount;
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    emit LogAddCollateral(_subAccount, _token, _amount);
  }

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(msg.sender, _subAccountId);

    LibMoneyMarket01.accureAllSubAccountDebtToken(_subAccount, moneyMarketDs);

    _removeCollateral(_subAccount, _token, _removeAmount, moneyMarketDs);

    moneyMarketDs.collats[_token] -= _removeAmount;

    ERC20(_token).safeTransfer(msg.sender, _removeAmount);

    emit LogRemoveCollateral(_subAccount, _token, _removeAmount);
  }

  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _fromSubAccount = LibMoneyMarket01.getSubAccount(msg.sender, _fromSubAccountId);

    LibMoneyMarket01.accureAllSubAccountDebtToken(_fromSubAccount, moneyMarketDs);

    _removeCollateral(_fromSubAccount, _token, _amount, moneyMarketDs);

    address _toSubAccount = LibMoneyMarket01.getSubAccount(msg.sender, _toSubAccountId);

    LibDoublyLinkedList.List storage toSubAccountCollateralList = moneyMarketDs.subAccountCollats[_toSubAccount];
    if (toSubAccountCollateralList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      toSubAccountCollateralList.init();
    }
    uint256 _newAmount = toSubAccountCollateralList.getAmount(_token) + _amount;
    toSubAccountCollateralList.addOrUpdate(_token, _newAmount);

    emit LogTransferCollateral(_fromSubAccount, _toSubAccount, _token, _amount);
  }

  function getCollaterals(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountCollateralList = moneyMarketDs.subAccountCollats[_subAccount];

    return subAccountCollateralList.getAll();
  }

  function collats(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.collats[_token];
  }

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);
  }

  function _validateAddCollateral(
    address _token,
    uint256 _collateralAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    if (moneyMarketDs.tokenConfigs[_token].tier != LibMoneyMarket01.AssetTier.COLLATERAL) {
      revert CollateralFacet_InvalidAssetTier();
    }

    if (_collateralAmount + moneyMarketDs.collats[_token] > moneyMarketDs.tokenConfigs[_token].maxCollateral) {
      revert CollateralFacet_ExceedCollateralLimit();
    }
  }

  function _removeCollateral(
    address _subAccount,
    address _token,
    uint256 _removeAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage _subAccountCollatList = moneyMarketDs.subAccountCollats[_subAccount];

    uint256 _collateralAmount = _subAccountCollatList.getAmount(_token);

    if (_removeAmount > _collateralAmount) {
      revert CollateralFacet_TooManyCollateralRemoved();
    }

    _subAccountCollatList.updateOrRemove(_token, _collateralAmount - _removeAmount);

    uint256 _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);

    (uint256 _totalUsedBorrowedPower, ) = LibMoneyMarket01.getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);

    // violate check-effect pattern for gas optimization, will change after come up with a way that doesn't loop
    if (_totalBorrowingPower < _totalUsedBorrowedPower) {
      revert CollateralFacet_BorrowingPowerTooLow();
    }
  }
}
