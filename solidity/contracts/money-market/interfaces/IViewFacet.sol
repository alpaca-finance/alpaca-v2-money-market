// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IViewFacet {
  function getProtocolReserve(address _token) external view returns (uint256 _reserve);

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getOverCollatDebtSharesOfSubAccount(address _account, uint256 _subAccountId)
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

  function getDebtLastAccrueTime(address _token) external view returns (uint256);

  function pendingInterest(address _token) external view returns (uint256);

  function debtValues(address _token) external view returns (uint256);

  function getOverCollatDebtSharesOfToken(address _token) external view returns (uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function getOverCollatSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256 _debtShare, uint256 _debtAmount);

  function getAllSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTotalCollatOfToken(address _token) external view returns (uint256);

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256);

  function getTotalToken(address _token) external view returns (uint256);

  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _shareAmount);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);

  function nonCollatGetDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory);

  function getNonCollatTotalUsedBorrowingPower(address _account)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset);

  function nonCollatGetDebt(address _account, address _token) external view returns (uint256);

  function nonCollatGetTokenDebt(address _token) external view returns (uint256);

  function nonCollatBorrowLimitUSDValues(address _account) external view returns (uint256);

  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256);
}
