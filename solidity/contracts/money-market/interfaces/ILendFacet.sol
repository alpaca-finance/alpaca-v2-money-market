// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILendFacet {
  function deposit(address _token, uint256 _amount) external;

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);

  function depositETH() external payable;

  function withdrawETH(address _ibWNativeToken, uint256 _shareAmount) external;

  function openMarket(address _token) external returns (address);

  error LendFacet_InvalidToken(address _token);
  error LendFacet_InvalidAddress(address _addr);
  error LendFacet_InvalidAmount(uint256 _amount);
}
