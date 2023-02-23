// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface ILendFacet {
  error LendFacet_InvalidToken(address _token);

  function deposit(
    address _for,
    address _token,
    uint256 _amount
  ) external returns (uint256 _shareAmount);

  function withdraw(
    address _for,
    address _ibToken,
    uint256 _shareAmount
  ) external returns (uint256 _shareValue);
}
