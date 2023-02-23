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

    // check if the money market is live
    LibMoneyMarket01.onlyLive(moneyMarketDs);

    // revert if borrower not in the whitelisted
    if (!moneyMarketDs.nonCollatBorrowerOk[msg.sender]) {
      revert NonCollatBorrowFacet_Unauthorized();
    }

    // accrue interest for borrowed debt token, to mint share correctly
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // accrue all debt tokens under account
    // total used borrowing power is calculated from all debt token of the account
    LibMoneyMarket01.accrueNonCollatBorrowedPositionsOf(msg.sender, moneyMarketDs);

    // validate before borrowing
    //  1. check if the market exists for the token
    //  2. check if the money market have enough token amount
    //  3. check if the borrower has enough borrowing power
    _validate(msg.sender, _token, _amount, moneyMarketDs);

    // update account debt values
    LibMoneyMarket01.nonCollatBorrow(msg.sender, _token, _amount, moneyMarketDs);

    // check if the money market have enough token amount in reserve to borrow
    if (_amount > moneyMarketDs.reserves[_token]) {
      revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    }
    // update the global reserve of the token
    moneyMarketDs.reserves[_token] -= _amount;
    // transfer the token to the borrower
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
    // accrue interest for borrowed debt token, to mint share correctly
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // get the existing debt value
    uint256 _oldDebtValue = LibMoneyMarket01.getNonCollatDebt(_account, _token, moneyMarketDs);
    // if the amount to repay is more than the existing debt, repay only the existing debt
    // otherwise repay debt for the amount to repay
    uint256 _debtToRemove = _oldDebtValue > _repayAmount ? _repayAmount : _oldDebtValue;

    // transfer only amount to repay to money market
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _debtToRemove);

    // remove the debt from the account
    _removeDebt(_account, _token, _oldDebtValue, _debtToRemove, moneyMarketDs);

    // update the global reserve of the token, as a result more borrowing can be made
    moneyMarketDs.reserves[_token] += _debtToRemove;

    emit LogNonCollatRepay(_account, _token, _debtToRemove);
  }

  /// @dev Remove the debt from the account
  /// @param _account The account to remove debt from
  /// @param _token The token to remove debt for
  /// @param _oldAccountDebtValue The old debt value of the account
  /// @param _valueToRemove The amount to remove
  function _removeDebt(
    address _account,
    address _token,
    uint256 _oldAccountDebtValue,
    uint256 _valueToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // update account debt values
    moneyMarketDs.nonCollatAccountDebtValues[_account].updateOrRemove(_token, _oldAccountDebtValue - _valueToRemove);

    // get the old token debt value
    uint256 _oldTokenDebt = moneyMarketDs.nonCollatTokenDebtValues[_token].getAmount(_account);

    // update token debt
    moneyMarketDs.nonCollatTokenDebtValues[_token].updateOrRemove(_account, _oldTokenDebt - _valueToRemove);

    // update global debt
    moneyMarketDs.globalDebts[_token] -= _valueToRemove;

    // emit event
    emit LogNonCollatRemoveDebt(_account, _token, _valueToRemove);
  }

  /// @dev Validate the borrow
  /// @param _account The borrower
  /// @param _token The token to be borrowed
  /// @param _amount The amount to borrow
  /// @param moneyMarketDs The money market diamond storage
  function _validate(
    address _account,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // get ibToken address from _token
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    // check open market
    // revert if the market is not exist , the address of _ibToken will be 0x0
    if (_ibToken == address(0)) {
      revert NonCollatBorrowFacet_InvalidToken(_token);
    }

    // get total used borrowing power of the borrower
    uint256 _totalUsedBorrowingPower = LibMoneyMarket01.getTotalNonCollatUsedBorrowingPower(_account, moneyMarketDs);

    // check capacity of money market for _token
    _checkCapacity(_token, _amount, moneyMarketDs);

    // check borrowing power of the borrower
    _checkBorrowingPower(_totalUsedBorrowingPower, _token, _amount, moneyMarketDs);
  }

  /// @dev Check if the borrower has enough borrowing power
  /// @param _usedBorrowingPower The total used borrowing power of the borrower
  /// @param _token The token to be borrowed
  /// @param _amount The amount to borrow
  /// @param moneyMarketDs The money market diamond storage
  function _checkBorrowingPower(
    uint256 _usedBorrowingPower,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    /// @dev: check the gas optimization on oracle call
    // get price of the token in USD for borrowing power calculation
    uint256 _tokenPrice = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);

    // get token config
    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    // get borrowing power limit of the borrower
    uint256 _borrowingPower = moneyMarketDs.protocolConfigs[msg.sender].borrowingPowerLimit;
    // get borrowing power of the new borrowing
    uint256 _newUsedBorrowingPower = LibMoneyMarket01.usedBorrowingPower(
      _amount,
      _tokenPrice,
      _tokenConfig.borrowingFactor,
      _tokenConfig.to18ConversionFactor
    );

    // check if the borrower has enough borrowing power
    // if used borrowing power + new used borrowing power exceed borrowing power, the borrow is not allowed
    if (_borrowingPower < _usedBorrowingPower + _newUsedBorrowingPower) {
      revert NonCollatBorrowFacet_BorrowingValueTooHigh(_borrowingPower, _usedBorrowingPower, _newUsedBorrowingPower);
    }
  }

  /// @dev Check if the token has enough capacity for borrower
  ///      Capacity is the amount of token that can be borrowed
  /// @param _token The token to be borrowed
  /// @param _borrowAmount The amount to borrow
  /// @param moneyMarketDs The money market diamond storage
  function _checkCapacity(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // get money market _token balance
    // balance = total _token balance - collateral _token balance
    uint256 _mmTokenBalance = IERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];

    // check if money market has enough _token balance to be borrowed
    if (_mmTokenBalance < _borrowAmount) {
      revert NonCollatBorrowFacet_NotEnoughToken(_borrowAmount);
    }

    // check if accumulated borrowAmount exceed global limit
    // if borrowing amount + global debt exceed max borrow amount of _token, the borrow is not allowed
    if (_borrowAmount + moneyMarketDs.globalDebts[_token] > moneyMarketDs.tokenConfigs[_token].maxBorrow) {
      revert NonCollatBorrowFacet_ExceedBorrowLimit();
    }

    // check if accumulated borrowAmount exceed account limit
    // if borrowing amount + borrowed amount exceed max _token borrow amount of the account, the borrow is not allowed
    if (
      _borrowAmount + moneyMarketDs.nonCollatAccountDebtValues[msg.sender].getAmount(_token) >
      moneyMarketDs.protocolConfigs[msg.sender].maxTokenBorrow[_token]
    ) {
      revert NonCollatBorrowFacet_ExceedAccountBorrowLimit();
    }
  }
}
