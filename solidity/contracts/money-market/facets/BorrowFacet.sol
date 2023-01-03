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

    (uint256 _oldSubAccountDebtShare, ) = LibMoneyMarket01.getOverCollatDebt(_subAccount, _token, moneyMarketDs);

    uint256 _actualShareToRepay = LibFullMath.min(_oldSubAccountDebtShare, _debtShareToRepay);

    uint256 _amountToRepay = LibShareUtil.shareToValue(
      _actualShareToRepay,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );

    _validateRepay(_subAccount, _token, _oldSubAccountDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    _removeDebt(_subAccount, _token, _oldSubAccountDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    // transfer only amount to repay
    moneyMarketDs.reserves[_token] += _amountToRepay;
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountToRepay);

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

    (uint256 _oldSubAccountDebtShare, ) = LibMoneyMarket01.getOverCollatDebt(_subAccount, _token, moneyMarketDs);

    uint256 _actualShareToRepay = LibFullMath.min(
      _debtShareToRepay,
      LibFullMath.min(_oldSubAccountDebtShare, _collateralAsShare)
    );

    uint256 _amountToRepay = LibShareUtil.shareToValue(
      _actualShareToRepay,
      moneyMarketDs.overCollatDebtValues[_token],
      moneyMarketDs.overCollatDebtShares[_token]
    );

    _validateRepay(_subAccount, _token, _oldSubAccountDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

    _removeDebt(_subAccount, _token, _oldSubAccountDebtShare, _actualShareToRepay, _amountToRepay, moneyMarketDs);

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
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRepay,
    uint256 _amountToRepay,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // update user debtShare
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_token, _oldSubAccountDebtShare - _shareToRepay);

    // update over collat debtShare
    moneyMarketDs.overCollatDebtShares[_token] -= _shareToRepay;
    moneyMarketDs.overCollatDebtValues[_token] -= _amountToRepay;

    // update global debt
    moneyMarketDs.globalDebts[_token] -= _amountToRepay;

    // emit event
    emit LogRemoveDebt(_subAccount, _token, _shareToRepay, _amountToRepay);
  }

  function _validateRepay(
    address _subAccount,
    address _repayToken,
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRepay,
    uint256 _amountToRepay,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // allow repay entire debt, early return to save gas
    if (_oldSubAccountDebtShare == _shareToRepay) return;

    // if partial repay, check if totalBorrowingPower after repaid more than minimum
    (uint256 _totalUsedBorrowingPower, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_subAccount, moneyMarketDs);

    (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_repayToken, moneyMarketDs);
    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_repayToken];
    uint256 _borrowingPowerToRepay = LibMoneyMarket01.usedBorrowingPower(
      _amountToRepay * _tokenConfig.to18ConversionFactor,
      _tokenPrice,
      _tokenConfig.borrowingFactor
    );

    uint256 _totalUsedBorrowingPowerAfterRepay = _totalUsedBorrowingPower - _borrowingPowerToRepay;

    if (_totalUsedBorrowingPowerAfterRepay < moneyMarketDs.minUsedBorrowingPower)
      revert BorrowFacet_TotalUsedBorrowingPowerTooLow();
  }

  function _validateBorrow(
    address _subAccount,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    // check open market
    if (_ibToken == address(0)) {
      revert BorrowFacet_InvalidToken(_token);
    }

    // check asset tier
    uint256 _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);

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

    _checkCapacity(_token, _amount, moneyMarketDs);

    _checkBorrowingPower(_totalBorrowingPower, _totalUsedBorrowingPower, _token, _amount, moneyMarketDs);
  }

  // TODO: gas optimize on oracle call
  function _checkBorrowingPower(
    uint256 _totalBorrowingPower,
    uint256 _totalUsedBorrowingPower,
    address _borrowingToken,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_borrowingToken, moneyMarketDs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_borrowingToken];

    uint256 _usingBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
      _amount * _tokenConfig.to18ConversionFactor,
      _tokenPrice,
      _tokenConfig.borrowingFactor
    );

    uint256 _newTotalUsedBorrowingPower = _totalUsedBorrowingPower + _usingBorrowingPower;

    if (_newTotalUsedBorrowingPower < moneyMarketDs.minUsedBorrowingPower)
      revert BorrowFacet_TotalUsedBorrowingPowerTooLow();

    if (_totalBorrowingPower < _newTotalUsedBorrowingPower)
      revert BorrowFacet_BorrowingValueTooHigh(_totalBorrowingPower, _totalUsedBorrowingPower, _usingBorrowingPower);
  }

  function _checkCapacity(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    if (moneyMarketDs.reserves[_token] < _borrowAmount) {
      revert BorrowFacet_NotEnoughToken(_borrowAmount);
    }

    if (_borrowAmount + moneyMarketDs.globalDebts[_token] > moneyMarketDs.tokenConfigs[_token].maxBorrow) {
      revert BorrowFacet_ExceedBorrowLimit();
    }
  }

  function accrueInterest(address _token) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);
  }
}
