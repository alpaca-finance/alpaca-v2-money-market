// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

// interfaces
import { IViewFacet } from "../interfaces/IViewFacet.sol";

contract ViewFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function getProtocolReserve(address _token) external view returns (uint256 _reserve) {
    return LibMoneyMarket01.moneyMarketDiamondStorage().protocolReserves[_token];
  }

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return moneyMarketDs.tokenConfigs[_token];
  }

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPowerUSDValue = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
  }

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowingPower(
      _subAccount,
      moneyMarketDs
    );
  }

  function getDebtLastAccrueTime(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtLastAccrueTime[_token];
  }

  function pendingInterest(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.pendingInterest(_token, moneyMarketDs);
  }

  function debtValues(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtValues[_token];
  }

  function getFloatingBalance(address _token) external view returns (uint256 _floating) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _floating = LibMoneyMarket01.getFloatingBalance(_token, moneyMarketDs);
  }

  function getOverCollatDebtSharesOfToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtShares[_token];
  }

  function getOverCollatDebtSharesOfSubAccount(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountDebtShares = moneyMarketDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  function getGlobalDebt(address _token) external view returns (uint256, uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return (moneyMarketDs.debtShares[_token], moneyMarketDs.debtValues[_token]);
  }

  function getOverCollatSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_debtShare, _debtAmount) = LibMoneyMarket01.getOverCollatDebt(_subAccount, _token, moneyMarketDs);
  }

  function getAllSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountCollateralList = moneyMarketDs.subAccountCollats[_subAccount];

    return subAccountCollateralList.getAll();
  }

  function getTotalCollatOfToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.collats[_token];
  }

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);
  }

  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _ibShareAmount)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    (, _ibShareAmount) = LibMoneyMarket01.getShareAmountFromValue(_token, _ibToken, _underlyingAmount, moneyMarketDs);
  }

  function getTotalToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);
  }

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // total token + pending interest that belong to lender
    _totalToken = LibMoneyMarket01.getTotalTokenWithPendingInterest(_token, moneyMarketDs);
  }

  function getNonCollatTotalUsedBorrowingPower(address _account)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowingPower(_account, moneyMarketDs);
  }

  function getNonCollatBorrowingPower(address _account) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.protocolConfigs[_account].borrowLimitUSDValue;
  }

  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256 _interestRate) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _interestRate = LibMoneyMarket01.getNonCollatInterestRate(_account, _token, moneyMarketDs);
  }

  function getNonCollatAccountDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibDoublyLinkedList.List storage _debtShares = moneyMarketDs.nonCollatAccountDebtValues[_account];

    return _debtShares.getAll();
  }

  function getNonCollatAccountDebt(address _account, address _token) external view returns (uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _debtAmount = LibMoneyMarket01.getNonCollatDebt(_account, _token, moneyMarketDs);
  }

  function getNonCollatTokenDebt(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return LibMoneyMarket01.getNonCollatTokenDebt(_token, moneyMarketDs);
  }
}