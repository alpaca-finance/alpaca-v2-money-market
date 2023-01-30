// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IMoneyMarket {
  function getTotalToken(address _token) external view returns (uint256);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);
}
