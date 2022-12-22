// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";

interface ILYFViewFacet {
  // ILYFFarmFacet
  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory);

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue);

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue);

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken
  ) external view returns (uint256, uint256);

  function getGlobalDebt(address _token, address _lpToken) external view returns (uint256, uint256);

  function debtLastAccrueTime(address _token, address _lpToken) external view returns (uint256);

  function pendingInterest(address _token, address _lpToken) external view returns (uint256);

  function debtValues(address _token, address _lpToken) external view returns (uint256);

  function debtShares(address _token, address _lpToken) external view returns (uint256);

  function pendingRewards(address _lpToken) external view returns (uint256);

  function getMMDebt(address _token) external view returns (uint256);

  function lpValues(address _lpToken) external view returns (uint256);

  function lpShares(address _lpToken) external view returns (uint256);

  function lpConfigs(address _lpToken) external view returns (LibLYF01.LPConfig memory);

  // ILYFCollateralFacet
  function getCollaterals(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function collats(address _token) external view returns (uint256);

  function subAccountCollatAmount(address _subAccount, address _token) external view returns (uint256);

  // Admin
  function oracle() external view returns (address);
}
