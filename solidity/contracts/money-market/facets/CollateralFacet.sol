// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { ICollateralFacet } from "../interfaces/ICollateralFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract CollateralFacet is ICollateralFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;
  using SafeCast for int256;

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
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibMoneyMarket01.addCollat(_subAccount, _token, _amount, moneyMarketDs);

    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

    emit LogAddCollateral(_subAccount, _token, _amount);
  }

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(msg.sender, _subAccountId);

    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    LibMoneyMarket01.removeCollat(_subAccount, _token, _removeAmount, moneyMarketDs);

    IERC20(_token).safeTransfer(msg.sender, _removeAmount);

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
    LibMoneyMarket01.accrueBorrowedPositionsOf(_fromSubAccount, moneyMarketDs);
    LibMoneyMarket01.removeCollatFromSubAccount(_fromSubAccount, _token, _amount, moneyMarketDs);

    address _toSubAccount = LibMoneyMarket01.getSubAccount(msg.sender, _toSubAccountId);
    LibMoneyMarket01.transferCollat(_toSubAccount, _token, _amount, moneyMarketDs);

    emit LogTransferCollateral(_fromSubAccount, _toSubAccount, _token, _amount);
  }
}
