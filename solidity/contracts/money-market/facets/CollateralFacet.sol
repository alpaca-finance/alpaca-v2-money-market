// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ICollateralFacet } from "../interfaces/ICollateralFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title CollateralFacet is dedicated to adding and removing collateral from subaccount
contract CollateralFacet is ICollateralFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;
  using SafeCast for int256;

  event LogTransferCollateral(
    address indexed _account,
    uint256 indexed _fromSubAccountId,
    uint256 indexed _toSubAccountId,
    address _token,
    uint256 _amount
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Add a token to a subaccount as a collateral
  /// @param _account The account to add collateral to
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The collateral token
  /// @param _amount The amount to add
  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // While there's no impact if interest of all of the borrowed tokens have not been accrued
    // Interests are accrued for code consistency
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // Pull the token from msg.sender
    // This should revert if the incoming token has fee on transfer
    LibMoneyMarket01.pullExactTokens(_token, msg.sender, _amount);

    // Book the collateral to subaccount's accounting
    // If the collateral token is ibToken, the ibToken should be staked at miniFL contract
    LibMoneyMarket01.addCollatToSubAccount(_account, _subAccount, _token, _amount, moneyMarketDs);
  }

  /// @notice Remove a collateral token from a subaccount
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The collateral token
  /// @param _removeAmount The amount to remove
  function removeCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _removeAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // accrue every debts for all token borrowed from this subaccount
    // This is to ensure that the subaccount's health check calculation below
    // already took unaccrued instests into account
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // Remove collateral from subaccount's accounting
    // The physical token of collateral token should be within MM Diamond
    LibMoneyMarket01.removeCollatFromSubAccount(_account, _subAccount, _token, _removeAmount, moneyMarketDs);

    // Do a final subaccount health check as the subaccount should not be at risk of liquidation
    // after the collateral was removed
    LibMoneyMarket01.validateSubaccountIsHealthy(_subAccount, moneyMarketDs);

    // Transfer the token back to account manager. Not the subaccount owner.
    IERC20(_token).safeTransfer(msg.sender, _removeAmount);
  }

  /// @notice Transfer the collateral from one subaccount to another subaccount
  /// @param _fromSubAccountId An index to derive the subaccount to transfer from
  /// @param _toSubAccountId An index to derive the subaccount to transfer to
  /// @param _token The token to transfer
  /// @param _amount The amount to transfer
  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    if (_fromSubAccountId == _toSubAccountId) {
      revert CollateralFacet_NoSelfTransfer();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _fromSubAccount = LibMoneyMarket01.getSubAccount(msg.sender, _fromSubAccountId);
    LibMoneyMarket01.accrueBorrowedPositionsOf(_fromSubAccount, moneyMarketDs);
    LibMoneyMarket01.removeCollatFromSubAccount(msg.sender, _fromSubAccount, _token, _amount, moneyMarketDs);
    LibMoneyMarket01.validateSubaccountIsHealthy(_fromSubAccount, moneyMarketDs);

    address _toSubAccount = LibMoneyMarket01.getSubAccount(msg.sender, _toSubAccountId);
    LibMoneyMarket01.addCollatToSubAccount(msg.sender, _toSubAccount, _token, _amount, moneyMarketDs);

    emit LogTransferCollateral(msg.sender, _fromSubAccountId, _toSubAccountId, _token, _amount);
  }
}
