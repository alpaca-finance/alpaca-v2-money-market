// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { INonCollatBorrowFacet } from "../interfaces/INonCollatBorrowFacet.sol";

contract NonCollatBorrowFacet is INonCollatBorrowFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogNonCollatRemoveDebt(address indexed _account, address indexed _token, uint256 _removeDebtAmount);

  event LogNonCollatRepay(address indexed _user, address indexed _token, uint256 _actualRepayAmount);

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function nonCollatBorrow(address _token, uint256 _amount) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    if (!moneyMarketDs.nonCollatBorrowerOk[msg.sender]) {
      revert NonCollatBorrowFacet_Unauthorized();
    }

    _validate(msg.sender, _token, _amount, moneyMarketDs);

    LibDoublyLinkedList.List storage debtValue = moneyMarketDs.nonCollatAccountDebtValues[msg.sender];

    if (debtValue.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      debtValue.init();
    }

    LibDoublyLinkedList.List storage tokenDebts = moneyMarketDs.nonCollatTokenDebtValues[_token];

    if (tokenDebts.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      tokenDebts.init();
    }

    // update account debt
    uint256 _newAccountDebt = debtValue.getAmount(_token) + _amount;
    uint256 _newTokenDebt = tokenDebts.getAmount(msg.sender) + _amount;

    debtValue.addOrUpdate(_token, _newAccountDebt);

    tokenDebts.addOrUpdate(msg.sender, _newTokenDebt);

    // update global debt

    moneyMarketDs.globalDebts[_token] += _amount;

    if (_amount > moneyMarketDs.reserves[_token]) revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    moneyMarketDs.reserves[_token] -= _amount;
    ERC20(_token).safeTransfer(msg.sender, _amount);
  }

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    uint256 _oldDebtValue = _getDebt(_account, _token, moneyMarketDs);

    uint256 _debtToRemove = _oldDebtValue > _repayAmount ? _repayAmount : _oldDebtValue;

    _removeDebt(_account, _token, _oldDebtValue, _debtToRemove, moneyMarketDs);

    // transfer only amount to repay
    moneyMarketDs.reserves[_token] += _debtToRemove;
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _debtToRemove);

    emit LogNonCollatRepay(_account, _token, _debtToRemove);
  }

  function nonCollatGetDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibDoublyLinkedList.List storage debtShares = moneyMarketDs.nonCollatAccountDebtValues[_account];

    return debtShares.getAll();
  }

  function nonCollatGetDebt(address _account, address _token) external view returns (uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _debtAmount = _getDebt(_account, _token, moneyMarketDs);
  }

  function _getDebt(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _debtAmount) {
    _debtAmount = moneyMarketDs.nonCollatAccountDebtValues[_account].getAmount(_token);
  }

  function nonCollatGetTokenDebt(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return LibMoneyMarket01.getNonCollatTokenDebt(_token, moneyMarketDs);
  }

  function _removeDebt(
    address _account,
    address _token,
    uint256 _oldAccountDebtValue,
    uint256 _valueToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // update user debtShare
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

    // check credit
    (uint256 _totalBorrowedUSDValue, ) = LibMoneyMarket01.getTotalUsedBorrowingPower(_account, moneyMarketDs);

    _checkBorrowingPower(_totalBorrowedUSDValue, _token, _amount, moneyMarketDs);

    _checkAvailableAndTokenLimit(_token, _amount, moneyMarketDs);
  }

  // TODO: gas optimize on oracle call
  function _checkBorrowingPower(
    uint256 _borrowedValue,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    uint256 _borrowingPower = moneyMarketDs.protocolConfigs[msg.sender].borrowLimitUSDValue;
    uint256 _borrowingUSDValue = LibMoneyMarket01.usedBorrowingPower(
      _amount * _tokenConfig.to18ConversionFactor,
      _tokenPrice,
      _tokenConfig.borrowingFactor
    );
    if (_borrowingPower < _borrowedValue + _borrowingUSDValue) {
      revert NonCollatBorrowFacet_BorrowingValueTooHigh(_borrowingPower, _borrowedValue, _borrowingUSDValue);
    }
  }

  function _checkAvailableAndTokenLimit(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
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

  function nonCollatGetTotalUsedBorrowingPower(address _account)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowingPower(_account, moneyMarketDs);
  }

  function nonCollatBorrowLimitUSDValues(address _account) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.protocolConfigs[_account].borrowLimitUSDValue;
  }

  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256 _pendingInterest) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _pendingInterest = LibMoneyMarket01.getNonCollatInterestRate(_account, _token, moneyMarketDs);
  }
}
