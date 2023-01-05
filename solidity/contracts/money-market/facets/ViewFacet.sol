// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

// ---- Interfaces ---- //
import { IViewFacet } from "../interfaces/IViewFacet.sol";

/// @title ViewFacet is dediciated to all view function used by external sources
contract ViewFacet is IViewFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  /// @notice Get the address of interest bearing token for the lending token
  /// @param _token The lending token
  /// @return The address of interest bearing token associated with
  function getIbTokenFromToken(address _token) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.tokenToIbTokens[_token];
  }

  /// @notice Get the underlying token from interest bearing token
  /// @param _ibToken The interest bearing token address
  /// @return The address of underlying token
  function getTokenFromIbToken(address _ibToken) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.ibTokenToTokens[_ibToken];
  }

  /// @notice Get the protocol reserve from interest collecting
  /// @param _token The token that has reserve
  /// @return _reserve The amount of reserve for that token
  function getProtocolReserve(address _token) external view returns (uint256 _reserve) {
    return LibMoneyMarket01.moneyMarketDiamondStorage().protocolReserves[_token];
  }

  /// @notice Get the configuration of the lending token
  /// @param _token The token
  /// @return The struct of TokenConfig
  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return moneyMarketDs.tokenConfigs[_token];
  }

  /// @notice Get the total borrowing power of the subaccount
  /// @param _account The main account
  /// @param _subAccountId The index to derive the subaccount
  /// @return _totalBorrowingPower Total borrowing power
  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPower)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
  }

  /// @notice Get the total used borrowing power of the subaccount
  /// @param _account The main account
  /// @param _subAccountId The index to derive the subaccount
  /// @return _totalUsedBorrowingPower Total borrowing power
  /// @return _hasIsolateAsset True if there's isolate asset under the subaccount
  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_totalUsedBorrowingPower, _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowingPower(
      _subAccount,
      moneyMarketDs
    );
  }

  /// @notice Get the total used borrowing power of the non collat account
  /// @param _account The address of non collat borrower
  /// @return _totalUsedBorrowingPower Total borrowing power
  function getTotalNonCollatUsedBorrowingPower(address _account)
    external
    view
    returns (uint256 _totalUsedBorrowingPower)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _totalUsedBorrowingPower = LibMoneyMarket01.getTotalNonCollatUsedBorrowingPower(_account, moneyMarketDs);
  }

  /// @notice Get the timestamp of latest interest collection on a token
  /// @param _token The token that has collected the interest
  /// @return timestamp of accrual time
  function getDebtLastAccrueTime(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtLastAccrueTime[_token];
  }

  /// @notice Get pending interest of borrowed token include both over and non collateralized
  /// @param _token The token that has collected the interest
  /// @return The total amount of interest pending for collection
  function getGlobalPendingInterest(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.getGlobalPendingInterest(_token, moneyMarketDs);
  }

  /// @notice Get the total amount of borrowed token include both over and non collateralized
  /// @param _token The token that has been borrowed
  /// @return The total amount of debt
  function getGlobalDebtValue(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.globalDebts[_token];
  }

  /// @notice Get the total amount of borrowed token via over collat borrowing
  /// @param _token The token that has been borrowed
  /// @return The total amount of over collateralized debt
  function getOverCollatDebtValue(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.overCollatDebtValues[_token];
  }

  /// @notice Get the remaing token left for borrowing
  /// @param _token The token that has been borrowed
  /// @return _floating The total amount of token left for borrowing
  function getFloatingBalance(address _token) external view returns (uint256 _floating) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _floating = LibMoneyMarket01.getFloatingBalance(_token, moneyMarketDs);
  }

  /// @notice Get the total share in the over collateralized debt pool
  /// @param _token The token that has been borrowed
  /// @return The total shares in the pool
  function getOverCollatTokenDebtShares(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.overCollatDebtShares[_token];
  }

  /// @notice Get list of debt share for the subaccount in the over collateralized debt pool
  /// @param _account The main account
  /// @param _subAccountId The index to derive the subaccount
  /// @return Array of node containing shares of borrowed token in the debt pool
  function getOverCollatSubAccountDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountDebtShares = moneyMarketDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  /// @notice Get total shares and actual amount of over collateralized debt for the token
  /// @param _token The borrowed token
  /// @return The total debt shares
  /// @return The total amount of debt
  function getOverCollatTokenDebt(address _token) external view returns (uint256, uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return (moneyMarketDs.overCollatDebtShares[_token], moneyMarketDs.overCollatDebtValues[_token]);
  }

  /// @notice Get shares and actual amount of over collateralized debt for the token of the subaccount
  /// @param _account The main account
  /// @param _subAccountId The index used to derive the subaccount
  /// @param _token The borrowed token
  /// @return _debtShare The amount of debt share on the token under the subaccount
  /// @return _debtAmount The actual amount of debt on the token under the subaccount
  function getOverCollatSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_debtShare, _debtAmount) = LibMoneyMarket01.getOverCollatDebt(_subAccount, _token, moneyMarketDs);
  }

  /// @notice Get all the collateral under the subaccount
  /// @param _account The main account
  /// @param _subAccountId The index used to derive the subaccount
  /// @return Array of node that contain all the collateral under the subaccount
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

  /// @notice Get all total amount of token placed as a collateral
  /// @param _token The collateral token
  /// @return The total amount of token that is placed as a collateral
  function getTotalCollat(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.collats[_token];
  }

  /// @notice Get the amount of collateral token under the subaccount
  /// @param _subAccount The derived subaccount
  /// @param _token The token used as a collateral
  /// @return The amount of collateral
  function getOverCollatSubAccountCollatAmount(address _subAccount, address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);
  }

  /// @notice Get the amount of interest bearing token equivalent to the underlying amount
  /// @param _token The token used as a collateral
  /// @param _underlyingAmount The amount of underlying token
  /// @return _ibShareAmount The amount of interest bearing token
  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _ibShareAmount)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    (, _ibShareAmount) = LibMoneyMarket01.getShareAmountFromValue(_token, _ibToken, _underlyingAmount, moneyMarketDs);
  }

  /// @notice Get the total amount of token that's eligible for lender without pending interest
  /// @param _token The token lended
  /// @return The total amount of token
  function getTotalToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);
  }

  /// @notice Get the total amount of token that's eligible for lender with pending interest
  /// @param _token The token lended
  /// @return The total amount of token
  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // total token + pending interest that belong to lender
    return LibMoneyMarket01.getTotalTokenWithPendingInterest(_token, moneyMarketDs);
  }

  /// @notice Get the borrowing power of a non collateralized borrower
  /// @param _account The non collateralized borrower
  /// @return The borrowing power
  function getNonCollatBorrowingPower(address _account) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.protocolConfigs[_account].borrowLimitUSDValue;
  }

  /// @notice Get the interest rate specific on token for a particular non collateralized borrower
  /// @param _account The non collateralized borrower
  /// @param _token The borrowed token
  /// @return _interestRate The interest rate
  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256 _interestRate) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _interestRate = LibMoneyMarket01.getNonCollatInterestRate(_account, _token, moneyMarketDs);
  }

  /// @notice Get the list of borrowed tokens for a paricular non collateralized borrower
  /// @param _account The non collateralized borrower
  /// @return A array of node contain borrowed tokens
  function getNonCollatAccountDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibDoublyLinkedList.List storage _debtShares = moneyMarketDs.nonCollatAccountDebtValues[_account];

    return _debtShares.getAll();
  }

  /// @notice Get the amount of token borrowed by a particular non collateralized borrower
  /// @param _account The non collateralized borrower
  /// @param _token The borrowed token
  /// @return _debtAmount The amount of token borrowed by this particular non collateralized borrower
  function getNonCollatAccountDebt(address _account, address _token) external view returns (uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _debtAmount = LibMoneyMarket01.getNonCollatDebt(_account, _token, moneyMarketDs);
  }

  /// @notice Get the amount of token borrowed by all non collateralized borrowers
  /// @param _token The borrowed token
  /// @return _debtAmount The amount of token borrowed by non colleralized borrowers
  function getNonCollatTokenDebt(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return LibMoneyMarket01.getNonCollatTokenDebt(_token, moneyMarketDs);
  }

  /// @notice Get the liquidation configuration
  /// @return maximum of used borrowing power that can be liquidated
  /// @return the threshold that will allow liquidation
  function getLiquidationParams() external view returns (uint16, uint16) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return (moneyMarketDs.maxLiquidateBps, moneyMarketDs.liquidationThresholdBps);
  }

  /// @notice Get the maximum number of token for different use cases
  /// @return _maxNumOfCollat maximum number of collaterals per subaccount
  /// @return _maxNumOfDebt maximum number of debt per subaccount
  /// @return _maxNumOfOverCollatDebt maximum number of debt per non collateralized borrower
  function getMaxNumOfToken()
    external
    view
    returns (
      uint8 _maxNumOfCollat,
      uint8 _maxNumOfDebt,
      uint8 _maxNumOfOverCollatDebt
    )
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _maxNumOfCollat = moneyMarketDs.maxNumOfCollatPerSubAccount;
    _maxNumOfDebt = moneyMarketDs.maxNumOfDebtPerSubAccount;
    _maxNumOfOverCollatDebt = moneyMarketDs.maxNumOfDebtPerNonCollatAccount;
  }

  /// @notice Get the minimum debt size that subaccount must maintain during borrow and repay
  function getMinDebtSize() external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return moneyMarketDs.minDebtSize;
  }

  /// @notice Get subaccount address by perform bitwise XOR on target address and subaccount id
  /// @param _account Target address to get subaccount from
  /// @param _subAccountId  Subaccount id of target address, value must be between 0 and 255 inclusive
  function getSubAccount(address _account, uint256 _subAccountId) external pure returns (address) {
    return LibMoneyMarket01.getSubAccount(_account, _subAccountId);
  }

  // TODO: natspec
  function getFeeParams()
    external
    view
    returns (
      uint16 _lendingFeeBps,
      uint16 _repurchaseRewardBps,
      uint16 _repurchaseFeeBps,
      uint16 _liquidationFeeBps
    )
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _lendingFeeBps = moneyMarketDs.lendingFeeBps;
    _repurchaseRewardBps = moneyMarketDs.repurchaseRewardBps;
    _repurchaseFeeBps = moneyMarketDs.repurchaseFeeBps;
    _liquidationFeeBps = moneyMarketDs.liquidationFeeBps;
  }
}
