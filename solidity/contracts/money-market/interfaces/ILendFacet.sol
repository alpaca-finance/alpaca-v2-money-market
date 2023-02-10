// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILendFacet {
  error LendFacet_InvalidToken(address _token);
  error LendFacet_InvalidAddress(address _addr);
  error LendFacet_InvalidAmount(uint256 _amount);

  function deposit(
    address _for,
    address _token,
    uint256 _amount
  ) external;

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);

  function depositETH() external payable;

  function withdrawETH(uint256 _shareAmount) external;
}
