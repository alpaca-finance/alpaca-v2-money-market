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

  event LogBorrow(address indexed _subAccount, address indexed _token, uint256 _borrowedAmount, uint256 _debtShare);
  event LogRemoveDebt(
    address indexed _subAccount,
    address indexed _token,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogRepay(address indexed _user, uint256 indexed _subAccountId, address _token, uint256 _actualRepayAmount);
  event LogRepayWithCollat(
    address indexed _user,
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
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to borrow
  /// @param _amount The amount to borrow
  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _subAccount = LibMoneyMarket01.getSubAccount(msg.sender, _subAccountId);

    // accrue interest for borrowed debt token, to mint share correctly
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // accrue all debt tokens under subaccount
    // because used borrowing power is calcualated from all debt token of sub account
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    _validateBorrow(_subAccount, _token, _amount, moneyMarketDs);

    uint256 _debtShare = LibMoneyMarket01.overCollatBorrow(_subAccount, _token, _amount, moneyMarketDs);

    IERC20(_token).safeTransfer(msg.sender, _amount);

    emit LogBorrow(_subAccount, _token, _amount, _debtShare);
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
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (uint256 _currentDebtShare, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebt(
      _subAccount,
      _token,
      moneyMarketDs
    );

    uint256 _actualShareToRepay = LibFullMath.min(_currentDebtShare, _debtShareToRepay);

    uint256 _amountToRepay = LibShareUtil.shareToValue(
      _actualShareToRepay,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );

    // transfer only amount to repay
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountToRepay);
    moneyMarketDs.reserves[_token] += _amountToRepay;

    _validateRepay(_token, _currentDebtShare, _currentDebtAmount, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    _removeDebt(_subAccount, _token, _currentDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    emit LogRepay(_account, _subAccountId, _token, _amountToRepay);
  }

  /// @notice Repay the debt for the subaccount using the same collateral
  /// @param _subAccountId An index to derive the subaccount
  /// @param _token The token to repay
  /// @param _debtShareToRepay The amount to repay
  function repayWithCollat(
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _subAccount = LibMoneyMarket01.getSubAccount(msg.sender, _subAccountId);
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // actual repay amount is minimum of collateral amount, debt amount, and repay amount
    uint256 _collateralAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);

    uint256 _collateralAsShare = LibShareUtil.valueToShare(
      _collateralAmount,
      moneyMarketDs.overCollatDebtShares[_token],
      moneyMarketDs.overCollatDebtValues[_token]
    );

    (uint256 _currentDebtShare, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebt(
      _subAccount,
      _token,
      moneyMarketDs
    );

    uint256 _actualShareToRepay = LibFullMath.min(
      _debtShareToRepay,
      LibFullMath.min(_currentDebtShare, _collateralAsShare)
    );

    uint256 _amountToRepay = LibShareUtil.shareToValue(
      _actualShareToRepay,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );

    _validateRepay(_token, _currentDebtShare, _currentDebtAmount, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    _removeDebt(_subAccount, _token, _currentDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    if (_amountToRepay > _collateralAmount) {
      revert BorrowFacet_TooManyCollateralRemoved();
    }

    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_token, _collateralAmount - _amountToRepay);
    moneyMarketDs.collats[_token] -= _amountToRepay;
    moneyMarketDs.reserves[_token] += _amountToRepay;

    emit LogRepayWithCollat(msg.sender, _subAccountId, _token, _amountToRepay);
  }

  function _removeDebt(
    address _subAccount,
    address _token,
    uint256 _currentSubAccountDebtShare,
    uint256 _shareToRemove,
    uint256 _amountToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // update user debtShare
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(
      _token,
      _currentSubAccountDebtShare - _shareToRemove
    );

    // update over collat debtShare
    moneyMarketDs.overCollatDebtShares[_token] -= _shareToRemove;
    moneyMarketDs.overCollatDebtValues[_token] -= _amountToRemove;

    // update global debt
    moneyMarketDs.globalDebts[_token] -= _amountToRemove;

    // emit event
    emit LogRemoveDebt(_subAccount, _token, _shareToRemove, _amountToRemove);
  }

  function _validateRepay(
    address _repayToken,
    uint256 _currentSubAccountDebtShare,
    uint256 _currentSubAccountDebtAmount,
    uint256 _shareToRepay,
    uint256 _amountToRepay,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // if partial repay, check if totalBorrowingPower after repaid more than minimum
    // no check if repay entire debt
    if (_currentSubAccountDebtShare > _shareToRepay) {
      (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);

      // check borrow + currentDebt < minDebtSize
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

    (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);
    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    // check borrow + currentDebt < minDebtSize
    (, uint256 _currentDebtAmount) = LibMoneyMarket01.getOverCollatDebt(_subAccount, _token, moneyMarketDs);
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
      _amount * _tokenConfig.to18ConversionFactor,
      _tokenPrice,
      _tokenConfig.borrowingFactor
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
