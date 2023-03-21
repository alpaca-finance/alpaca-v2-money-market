// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract MockInterestModel {
  uint256 internal interestRate;

  constructor(uint256 _rate) {
    interestRate = _rate;
  }

  function getInterestRate(
    uint256, /*debt*/
    uint256 /*floating*/
  ) external view returns (uint256 _rate) {
    _rate = interestRate;
  }

  function setInterestRate(uint256 _rate) external {
    interestRate = _rate;
  }
}
