// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IViewFacet {
  function getProtocolReserve(address _token) external view returns (uint256 _reserve);

  function tokenConfigs(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue);

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset);

  function getGlobalDebt(address _token) external view returns (uint256, uint256);

  function debtLastAccrueTime(address _token) external view returns (uint256);

  function pendingInterest(address _token) external view returns (uint256);

  function debtValues(address _token) external view returns (uint256);

  function debtShares(address _token) external view returns (uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256 _debtShare, uint256 _debtAmount);

  function getCollaterals(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function collats(address _token) external view returns (uint256);

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256);
}
