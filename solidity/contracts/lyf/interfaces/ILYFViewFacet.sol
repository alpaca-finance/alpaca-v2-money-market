// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";

interface ILYFViewFacet {
  function getOracle() external view returns (address);

  function getLpTokenConfig(address _lpToken) external view returns (LibLYF01.LPConfig memory);

  function getLpTokenAmount(address _lpToken) external view returns (uint256);

  function getLpTokenShare(address _lpToken) external view returns (uint256);

  function getSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTokenCollatAmount(address _token) external view returns (uint256);

  function getSubAccountTokenCollatAmount(address _subAccount, address _token) external view returns (uint256);

  function getMMDebt(address _token) external view returns (uint256);

  function getGlobalDebt(address _token, address _lpToken) external view returns (uint256, uint256);

  function getTokenDebtValue(address _token, address _lpToken) external view returns (uint256);

  function getTokenDebtShare(address _token, address _lpToken) external view returns (uint256);

  function getSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken
  ) external view returns (uint256, uint256);

  function getSubAccountDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory);

  function getDebtLastAccrueTime(address _token, address _lpToken) external view returns (uint256);

  function getPendingInterest(address _token, address _lpToken) external view returns (uint256);

  function getPendingReward(address _lpToken) external view returns (uint256);

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue);

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue);
}
