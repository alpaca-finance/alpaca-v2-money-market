// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendFacet {
  function deposit(address _token, uint256 _amount) external;

  function withdraw(address _ibToken, uint256 _shareAmount) external;

  function depositETH() external payable;

  function withdrawETH(address _ibWNativeToken, uint256 _shareAmount) external;

  function getTotalToken(address _token) external view returns (uint256);

  function openMarket(address _token) external returns (address);

  error LendFacet_InvalidToken(address _token);
  error LendFacet_NoTinyShares();
  error LendFacet_InvalidAmount(uint256 _amount);
}
