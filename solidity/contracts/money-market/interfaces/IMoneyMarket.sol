// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IMoneyMarket {
  function getTotalToken(address _token) external view returns (uint256);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function withdraw(
    address _for,
    address _ibToken,
    uint256 _shareAmount
  ) external returns (uint256 _shareValue);

  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function getGlobalPendingInterest(address _token) external view returns (uint256);

  function getGlobalDebtValue(address _token) external view returns (uint256);

  function getGlobalDebtValueWithPendingInterest(address _token) external view returns (uint256);

  function getDebtLastAccruedAt(address _token) external view returns (uint256);

  function setAccountManagersOk(address[] calldata _list, bool _isOk) external;

  function getAllSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getOracle() external view returns (address);

  function getOverCollatDebtSharesOf(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);
}
