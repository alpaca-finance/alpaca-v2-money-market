// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { ILYFViewFacet } from "../interfaces/ILYFViewFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

contract LYFViewFacet is ILYFViewFacet {
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  /// @notice Get the address of the oracle
  /// @return Address of the oracle
  function getOracle() external view returns (address) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return address(lyfDs.oracle);
  }

  /// @notice Get the configuration of LP token
  /// @param _lpToken The address of LP token
  /// @return Struct that contains configuration paramteres
  function getLpTokenConfig(address _lpToken) external view returns (LibLYF01.LPConfig memory) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpConfigs[_lpToken];
  }

  /// @notice Get the total amount of LP token that managed by the protocol
  /// @param _lpToken The address of LP token
  /// @return Amount of LP token
  function getLpTokenAmount(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpAmounts[_lpToken];
  }

  /// @notice Get the total amount of share for all LP Token that managed by the protocol
  /// @param _lpToken The address of LP token
  /// @return Amount of share
  function getLpTokenShare(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpShares[_lpToken];
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
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    LibDoublyLinkedList.List storage subAccountCollateralList = ds.subAccountCollats[_subAccount];
    return subAccountCollateralList.getAll();
  }

  /// @notice Get total amount of collat of a token
  /// @param _token The collateral token
  /// @return The total amount of token
  function getTokenCollatAmount(address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    return ds.collats[_token];
  }

  /// @notice Get the amount of collateral token under the subaccount
  /// @param _account The main account
  /// @param _subAccountId The index used to derive the subaccount
  /// @param _token The colalteral token
  /// @return The amount of collateral
  function getSubAccountTokenCollatAmount(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    return ds.subAccountCollats[_subAccount].getAmount(_token);
  }

  /// @notice Get the Debt that LYF owned MM
  /// @param _token The borrowed token
  /// @return _debtAmount The amount of borrowed token
  function getMMDebt(address _token) external view returns (uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _debtAmount = lyfDs.moneyMarket.getNonCollatAccountDebt(address(this), _token);
  }

  /// @notice Get the debt pool id from token and LP token
  /// @param _token The borrowed token
  /// @param _lpToken The destination LP of the borrowed token
  function getDebtPoolIdOf(address _token, address _lpToken) external view returns (uint256 _debtPoolId) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    _debtPoolId = lyfDs.debtPoolIds[_token][_lpToken];
  }

  /// @notice Get the debt pool information
  /// @param _debtPoolId The id of the debt pool
  /// @return A struct of DebtPoolInfo
  function getDebtPoolInfo(uint256 _debtPoolId) external view returns (LibLYF01.DebtPoolInfo memory) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtPoolInfos[_debtPoolId];
  }

  /// @notice Get the total amount of debt value in the debt pool
  /// @param _debtPoolId The id of the debt pool
  /// @return Amount of debt
  function getDebtPoolTotalValue(uint256 _debtPoolId) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtPoolInfos[_debtPoolId].totalValue;
  }

  /// @notice Get the total amount of debt share in the debt pool
  /// @param _debtPoolId The id of the debt pool
  /// @return Amount of debt share
  function getDebtPoolTotalShare(uint256 _debtPoolId) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtPoolInfos[_debtPoolId].totalShare;
  }

  /// @notice Get the debt share and amount of a subaccount
  /// @param _account The main account
  /// @param _subAccountId The index of the subaccount
  /// @param _token The borrowed token address
  /// @param _lpToken The LP token that assosicated with the borrow token
  function getSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken
  ) external view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtPoolId = lyfDs.debtPoolIds[_token][_lpToken];
    LibLYF01.DebtPoolInfo memory debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];

    _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtPoolId);
    _debtAmount = LibShareUtil.shareToValue(_debtShare, debtPoolInfo.totalValue, debtPoolInfo.totalShare);
  }

  /// @notice Get the list of all debt share and amount of a subaccount
  /// @param _account The main account
  /// @param _subAccountId The index of the subaccount
  /// @return Array of node containing shares of borrowed token in the debt pool
  function getAllSubAccountDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    LibUIntDoublyLinkedList.List storage subAccountDebtShares = lyfDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  /// @notice Get the timestamp of the last interest accruement
  /// @param _debtPoolId The id of the debt pool
  /// @return timestamp of the accruement
  function getDebtPoolLastAccruedAt(uint256 _debtPoolId) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtPoolInfos[_debtPoolId].lastAccruedAt;
  }

  /// @notice Get the pending interest of a debt pool
  /// @param _debtPoolId The id of the debt pool
  /// @return The amount of outstanding interest that hasn't been accrued
  function getDebtPoolPendingInterest(uint256 _debtPoolId) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    LibLYF01.DebtPoolInfo memory debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];
    return
      LibLYF01.getDebtPoolPendingInterest(
        lyfDs.moneyMarket,
        debtPoolInfo.interestModel,
        debtPoolInfo.token,
        block.timestamp - debtPoolInfo.lastAccruedAt,
        debtPoolInfo.totalValue
      );
  }

  /// @notice Get the pending reward waiting to be compounded
  /// @param _lpToken The LP token associated with reward
  function getPendingReward(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.pendingRewards[_lpToken];
  }

  /// @notice Get the total borrowing power of a subaccount
  /// @param _account The main account
  /// @param _subAccountId The index of the subaccount
  /// @return _totalBorrowingPower Sum of all borrowing power from collaterals
  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPower)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPower = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
  }

  /// @notice Get the total borrowing power of a subaccount that has been used
  /// @param _account The main account
  /// @param _subAccountId The index of the subaccount
  /// @return _totalUsedBorrowingPower Sum of all borrowing power used from outstanding debt
  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalUsedBorrowingPower)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    _totalUsedBorrowingPower = LibLYF01.getTotalUsedBorrowingPower(_subAccount, lyfDs);
  }

  /// @notice Get the maximum nuber of token configurations
  /// @return _maxNumOfCollat maximum number of collateral per subaccount
  /// @return _maxNumOfDebt maximum number of collateral in the list
  function getMaxNumOfToken() external view returns (uint8 _maxNumOfCollat, uint8 _maxNumOfDebt) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _maxNumOfCollat = lyfDs.maxNumOfCollatPerSubAccount;
    _maxNumOfDebt = lyfDs.maxNumOfDebtPerSubAccount;
  }

  /// @notice Get the minimum debt size per token per subaccount
  /// @return _minDebtSize Minimum debt size
  function getMinDebtSize() external view returns (uint256 _minDebtSize) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _minDebtSize = lyfDs.minDebtSize;
  }

  /// @notice Get the outstanding reserve available for lending of a token
  /// @param _token The borrowing token
  /// @return _reserveAmount The outstanding amount
  function getOutstandingBalanceOf(address _token) external view returns (uint256 _reserveAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    if (lyfDs.reserves[_token] > lyfDs.protocolReserves[_token]) {
      _reserveAmount = lyfDs.reserves[_token] - lyfDs.protocolReserves[_token];
    }
  }

  function getProtocolReserveOf(address _token) external view returns (uint256 _protocolReserveAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _protocolReserveAmount = lyfDs.protocolReserves[_token];
  }

  function getSubAccount(address _primary, uint256 _subAccountId) external pure returns (address _subAccount) {
    _subAccount = LibLYF01.getSubAccount(_primary, _subAccountId);
  }
}
