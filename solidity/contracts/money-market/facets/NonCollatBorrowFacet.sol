// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { INonCollatBorrowFacet } from "../interfaces/INonCollatBorrowFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title NonCollatBorrowFacet is dedicated to non collateralized borrowing
contract NonCollatBorrowFacet is INonCollatBorrowFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogNonCollatBorrow(address indexed _account, address indexed _token, uint256 _removeDebtAmount);
  event LogNonCollatRemoveDebt(address indexed _account, address indexed _token, uint256 _removeDebtAmount);
  event LogNonCollatRepay(address indexed _account, address indexed _token, uint256 _actualRepayAmount);

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Borrow without collaterals
  /// @param _token The token to be borrowed
  /// @param _amount The amount to borrow
  function nonCollatBorrow(address _token, uint256 _amount) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.onlyLive(moneyMarketDs);

    if (!moneyMarketDs.nonCollatBorrowerOk[msg.sender]) {
      revert NonCollatBorrowFacet_Unauthorized();
    }

    // accrue interest for borrowed debt token, to mint share correctly
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // accrue all debt tokens under account
    // total used borrowing power is calculated from all debt token of the account
    LibMoneyMarket01.accrueNonCollatBorrowedPositionsOf(msg.sender, moneyMarketDs);

    _validate(msg.sender, _token, _amount, moneyMarketDs);

    LibMoneyMarket01.nonCollatBorrow(msg.sender, _token, _amount, moneyMarketDs);

    if (_amount > moneyMarketDs.reserves[_token]) {
      revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    }
    moneyMarketDs.reserves[_token] -= _amount;
    IERC20(_token).safeTransfer(msg.sender, _amount);

    emit LogNonCollatBorrow(msg.sender, _token, _amount);
  }

  /// @notice Repay the debt
  /// @param _account The account to repay for
  /// @param _token The token to be repaid
  /// @param _repayAmount The amount to repay
  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    uint256 _oldDebtValue = LibMoneyMarket01.getNonCollatDebt(_account, _token, moneyMarketDs);

    uint256 _debtToRemove = _oldDebtValue > _repayAmount ? _repayAmount : _oldDebtValue;

    // transfer only amount to repay
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _debtToRemove);

    _removeDebt(_account, _token, _oldDebtValue, _debtToRemove, moneyMarketDs);

    moneyMarketDs.reserves[_token] += _debtToRemove;

    emit LogNonCollatRepay(_account, _token, _debtToRemove);
  }

  function _removeDebt(
    address _account,
    address _token,
    uint256 _oldAccountDebtValue,
    uint256 _valueToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // update account debt values
    moneyMarketDs.nonCollatAccountDebtValues[_account].updateOrRemove(_token, _oldAccountDebtValue - _valueToRemove);

    uint256 _oldTokenDebt = moneyMarketDs.nonCollatTokenDebtValues[_token].getAmount(_account);

    // update token debt
    moneyMarketDs.nonCollatTokenDebtValues[_token].updateOrRemove(_account, _oldTokenDebt - _valueToRemove);

    // update global debt

    moneyMarketDs.globalDebts[_token] -= _valueToRemove;

    // emit event
    emit LogNonCollatRemoveDebt(_account, _token, _valueToRemove);
  }

  function _validate(
    address _account,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    // check open market
    if (_ibToken == address(0)) {
      revert NonCollatBorrowFacet_InvalidToken(_token);
    }

    uint256 _totalUsedBorrowingPower = LibMoneyMarket01.getTotalNonCollatUsedBorrowingPower(_account, moneyMarketDs);

    _checkCapacity(_token, _amount, moneyMarketDs);

    _checkBorrowingPower(_totalUsedBorrowingPower, _token, _amount, moneyMarketDs);
  }

  function _checkBorrowingPower(
    uint256 _borrowedValue,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    /// @dev: check the gas optimization on oracle call
    uint256 _tokenPrice = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    uint256 _borrowingPower = moneyMarketDs.protocolConfigs[msg.sender].borrowLimitUSDValue;
    uint256 _borrowingUSDValue = LibMoneyMarket01.usedBorrowingPower(
      _amount,
      _tokenPrice,
      _tokenConfig.borrowingFactor,
      _tokenConfig.to18ConversionFactor
    );
    if (_borrowingPower < _borrowedValue + _borrowingUSDValue) {
      revert NonCollatBorrowFacet_BorrowingValueTooHigh(_borrowingPower, _borrowedValue, _borrowingUSDValue);
    }
  }

  function _checkCapacity(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _mmTokenBalance = IERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];

    if (_mmTokenBalance < _borrowAmount) {
      revert NonCollatBorrowFacet_NotEnoughToken(_borrowAmount);
    }

    // check if accumulated borrowAmount exceed global limit
    if (_borrowAmount + moneyMarketDs.globalDebts[_token] > moneyMarketDs.tokenConfigs[_token].maxBorrow) {
      revert NonCollatBorrowFacet_ExceedBorrowLimit();
    }

    // check if accumulated borrowAmount exceed account limit
    if (
      _borrowAmount + moneyMarketDs.nonCollatAccountDebtValues[msg.sender].getAmount(_token) >
      moneyMarketDs.protocolConfigs[msg.sender].maxTokenBorrow[_token]
    ) {
      revert NonCollatBorrowFacet_ExceedAccountBorrowLimit();
    }
  }
}
