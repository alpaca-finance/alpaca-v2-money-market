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
  /// @param _account Main account that collateral will be removed from
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
    // Additionally, withdraw the collateral token that should have been
    // staked at miniFL specifically if the collateral was ibToken
    // The physical token of collateral token should now have been at MM Diamond
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
    address _account,
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    // Prevent self transfer to be on a safe side of double accounting
    if (_fromSubAccountId == _toSubAccountId) {
      revert CollateralFacet_NoSelfTransfer();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _fromSubAccount = LibMoneyMarket01.getSubAccount(_account, _fromSubAccountId);

    // Accure all the debt tokens under the origin subaccount
    // This is to ensure that debt are updated and the health check is accurate
    LibMoneyMarket01.accrueBorrowedPositionsOf(_fromSubAccount, moneyMarketDs);

    // Remove the collateral from the origin subaccount
    LibMoneyMarket01.removeCollatFromSubAccount(_account, _fromSubAccount, _token, _amount, moneyMarketDs);

    // before proceeding to add the recently removed collateral to the destination subaccount's accounting
    // perform a health check. This should revert if the remove collateral operation result in
    // making the origin subaccount at risk of liquidation
    LibMoneyMarket01.validateSubaccountIsHealthy(_fromSubAccount, moneyMarketDs);

    address _toSubAccount = LibMoneyMarket01.getSubAccount(_account, _toSubAccountId);

    // Add the collateral to destination subaccount's accounting
    // The health check on the destination subaccount is not required as adding collateral
    // will always benefit the subaccount or at worst changes nothing
    LibMoneyMarket01.addCollatToSubAccount(_account, _toSubAccount, _token, _amount, moneyMarketDs);

    emit LogTransferCollateral(_account, _fromSubAccountId, _toSubAccountId, _token, _amount);
  }
}
