// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { IMasterChef } from "../../contracts/lyf/libraries/masterChef/IMasterChef.sol";

contract MockMasterChefV1 is IMasterChef {
  constructor() {}

  uint256 pid = 0;

  function deposit(uint256 _pid, uint256 _amount) external {}

  function withdraw(uint256 _pid, uint256 _amount) external {}

  function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256) {
    return (pid, _pid);
  }
}
