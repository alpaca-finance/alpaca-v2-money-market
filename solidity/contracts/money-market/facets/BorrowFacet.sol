// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { IBorrowFacet } from "../interfaces/IBorrowFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title BorrowFacet is dedicated to over collateralized borrowing and repayment
contract BorrowFacet is IBorrowFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;

  event LogRepay(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token,
    address _caller,
    uint256 _actualRepayAmount
  );
  event LogRepayWithCollat(
    address indexed _account,
    uint256 indexed _subAccountId,
    address _token,
    uint256 _actualRepayAmount
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Borrow a token agaist the placed collaterals
  /// @param _account Account owner
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to borrow
  /// @param _amount The amount to borrow
  function borrow(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.onlyLive(moneyMarketDs);

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // accrue interest for borrowed debt token, to mint share correctly
    // This is to handle the case where the subaccount is borrowing the token that has not been borrowed
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // accrue all debt tokens under subaccount
    // because used borrowing power is calcualated from all debt token of sub account
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // Validate if this borrowing transaction will violate the business rules
    // this includes insufficient borrowing power, borrowing below minimum debt size , etc.
    _validateBorrow(_subAccount, _token, _amount, moneyMarketDs);

    // Book the debt under the subaccount that the account manager act on behalf of
    LibMoneyMarket01.overCollatBorrow(_account, _subAccount, _token, _amount, moneyMarketDs);

    // Update the global reserve of the token, as a result less borrowing can be amde
    moneyMarketDs.reserves[_token] -= _amount;

    // Transfer the token back to account manager
    IERC20(_token).safeTransfer(msg.sender, _amount);
  }

  /// @notice Repay the debt for the subaccount
  /// @param _account The account to repay for
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to repay
  /// @param _debtShareToRepay The share amount of debt token to repay
  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // accrue all debt tokens under subaccount
    // because used borrowing power is calcualated from all debt token of sub account
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // Get the current debt amount and share of this token under the subaccount
    // The current debt share will be used to cap the maximum that can be repaid
    // The current debt amount will be used to check the minimum debt size after repaid
    (uint256 _currentDebtShare, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
      _subAccount,
      _token,
      moneyMarketDs
    );

    // The debt share that can be repaid should not exceed the current debt share
    // that the subaccount is holding
    uint256 _actualShareToRepay = LibFullMath.min(_currentDebtShare, _debtShareToRepay);

    // caching these variables to save gas from multiple reads
    uint256 _cachedDebtValue = moneyMarketDs.overCollatDebtValues[_token];
    uint256 _cachedDebtShare = moneyMarketDs.overCollatDebtShares[_token];

    // Find the actual underlying amount that need to be pulled from the share
    uint256 _actualAmountToRepay = LibShareUtil.shareToValue(_actualShareToRepay, _cachedDebtValue, _cachedDebtShare);

    // Pull the token from the account manager, the actual amount received will be used for debt accounting
    // In case somehow there's fee on transfer - which's might be introduced after the token was lent
    // Not reverting to ensure that repay transaction can be done even if there's fee on transfer
    _actualAmountToRepay = LibMoneyMarket01.unsafePullTokens(_token, msg.sender, _actualAmountToRepay);

    // Recalculate the debt share to remove in case there's fee on transfer
    _actualShareToRepay = LibShareUtil.valueToShare(_actualAmountToRepay, _cachedDebtShare, _cachedDebtValue);

    // Increase the reserve amount of the token as there's new physical token coming in
    moneyMarketDs.reserves[_token] += _actualAmountToRepay;

    // Check and revert if the repay transaction will violate the business rule
    // namely the debt size after repaid should be more than minimum debt size
    _validateRepay(
      _token,
      _currentDebtShare,
      _currentDebtAmount,
      _actualShareToRepay,
      _actualAmountToRepay,
      moneyMarketDs
    );

    // Remove the debt share from this subaccount's accounting
    // additionally, this library call will unstake the debt token
    // from miniFL and burn the debt token
    LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
      _account,
      _subAccount,
      _token,
      _actualShareToRepay,
      _actualAmountToRepay,
      moneyMarketDs
    );

    emit LogRepay(_account, _subAccountId, _token, msg.sender, _actualAmountToRepay);
  }

  /// @notice Repay the debt for the subaccount using the same collateral
  /// @param _account The account to repay for
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to repay
  /// @param _debtShareToRepay The amount to repay
  function repayWithCollat(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    // accrue all debt tokens under subaccount
    // because used borrowing power is calcualated from all debt token of sub account
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    uint256 _collateralAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);

    // Find the debt share equivalent of collateral token
    // Simply convert the amount of collateral token with respect to over collat debt shares and values
    uint256 _collateralAsShare = LibShareUtil.valueToShare(
      _collateralAmount,
      moneyMarketDs.overCollatDebtShares[_token],
      moneyMarketDs.overCollatDebtValues[_token]
    );

    // Get the current debt amount and share of this token under the subaccount
    // The current debt share will be used to cap the maximum that can be repaid
    // The current debt amount will be used to check the minimum debt size after repaid
    (uint256 _currentDebtShare, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
      _subAccount,
      _token,
      moneyMarketDs
    );

    // Maximum of debt share that can be removed should be the minimum of
    // 1. current debt share under the subaccount
    // 2. the input debt share intented to be removed
    // 3. the equivalent of debt share in collateral form
    uint256 _actualShareToRepay = LibFullMath.min(
      _debtShareToRepay,
      LibFullMath.min(_currentDebtShare, _collateralAsShare)
    );

    // Calculate the amount to be used in repay transaction
    uint256 _amountToRepay = LibShareUtil.shareToValue(
      _actualShareToRepay,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );

    // Check and revert if the repay transaction will violate the business rule
    // namely the debt size after repaid should be more than minimum debt size
    _validateRepay(_token, _currentDebtShare, _currentDebtAmount, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    // Remove the debt share from this subaccount's accounting
    // the actual token repaid will be from internal accounting transfer from
    // collateral to reserves
    LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
      _account,
      _subAccount,
      _token,
      _actualShareToRepay,
      _amountToRepay,
      moneyMarketDs
    );

    // Remove collateral from subaccount's accounting
    // Additionally, withdraw the collateral token that should have been
    // staked at miniFL specifically if the collateral was ibToken
    // The physical token of collateral token should now have been at MM Diamond
    LibMoneyMarket01.removeCollatFromSubAccount(_account, _subAccount, _token, _amountToRepay, moneyMarketDs);

    // Increase the reserves as the token has freed up
    moneyMarketDs.reserves[_token] += _amountToRepay;

    emit LogRepayWithCollat(_account, _subAccountId, _token, _amountToRepay);
  }

  function _validateRepay(
    address _repayToken,
    uint256 _currentSubAccountDebtShare,
    uint256 _currentSubAccountDebtAmount,
    uint256 _shareToRepay,
    uint256 _amountToRepay,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // if partial repay, check if debt after repaid more than minDebtSize
    // no check if repay entire debt
    if (_currentSubAccountDebtShare > _shareToRepay) {
      uint256 _tokenPrice = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

      if (
        ((_currentSubAccountDebtAmount - _amountToRepay) *
          moneyMarketDs.tokenConfigs[_repayToken].to18ConversionFactor *
          _tokenPrice) /
          1e18 <
        moneyMarketDs.minDebtSize
      ) {
        revert BorrowFacet_BorrowLessThanMinDebtSize();
      }
    }
  }

  function _validateBorrow(
    address _subAccount,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // check open market
    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) {
      revert BorrowFacet_InvalidToken(_token);
    }

    uint256 _tokenPrice = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);
    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    // check borrow + currentDebt < minDebtSize
    (, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
      _subAccount,
      _token,
      moneyMarketDs
    );
    if (
      ((_amount + _currentDebtAmount) * _tokenConfig.to18ConversionFactor * _tokenPrice) / 1e18 <
      moneyMarketDs.minDebtSize
    ) {
      revert BorrowFacet_BorrowLessThanMinDebtSize();
    }

    // check asset tier
    (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowingPower(
      _subAccount,
      moneyMarketDs
    );

    if (moneyMarketDs.tokenConfigs[_token].tier == LibMoneyMarket01.AssetTier.ISOLATE) {
      if (
        !moneyMarketDs.subAccountDebtShares[_subAccount].has(_token) &&
        moneyMarketDs.subAccountDebtShares[_subAccount].size > 0
      ) {
        revert BorrowFacet_InvalidAssetTier();
      }
    } else if (_hasIsolateAsset) {
      revert BorrowFacet_InvalidAssetTier();
    }

    // check if tokens in reserve is enough to be borrowed
    if (moneyMarketDs.reserves[_token] < _amount) {
      revert BorrowFacet_NotEnoughToken(_amount);
    }

    // check global borrowing limit
    if (_amount + moneyMarketDs.globalDebts[_token] > moneyMarketDs.tokenConfigs[_token].maxBorrow) {
      revert BorrowFacet_ExceedBorrowLimit();
    }

    // check used borrowing power after borrow exceed total borrowing power
    uint256 _borrowingPowerToBeUsed = LibMoneyMarket01.usedBorrowingPower(
      _amount,
      _tokenPrice,
      _tokenConfig.borrowingFactor,
      _tokenConfig.to18ConversionFactor
    );
    uint256 _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);

    if (_totalBorrowingPower < _totalUsedBorrowingPower + _borrowingPowerToBeUsed) {
      revert BorrowFacet_BorrowingValueTooHigh(_totalBorrowingPower, _totalUsedBorrowingPower, _borrowingPowerToBeUsed);
    }
  }

  function accrueInterest(address _token) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);
  }
}
