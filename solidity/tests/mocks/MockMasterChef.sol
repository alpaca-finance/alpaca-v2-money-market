// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { IMasterChefLike } from "../../contracts/lyf/interfaces/IMasterChefLike.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockMasterChef is IMasterChefLike {
  struct PoolInfo {
    address lpAddress;
    uint256 poolId;
  }

  mapping(uint256 => PoolInfo) poolInfo;
  mapping(uint256 => mapping(address => uint256)) userPosition;
  mapping(uint256 => mapping(address => uint256)) reward;

  constructor() {}

  function addLendingPool(address _lpAddress, uint256 _pid) external {
    poolInfo[_pid] = PoolInfo({ lpAddress: _lpAddress, poolId: _pid });
  }

  function deposit(uint256 _pid, uint256 _amount) external {
    ERC20(poolInfo[_pid].lpAddress).transferFrom(msg.sender, address(this), _amount);
    userPosition[_pid][msg.sender] += _amount;
  }

  function withdraw(uint256 _pid, uint256 _amount) external {
    ERC20(poolInfo[_pid].lpAddress).transfer(msg.sender, _amount);
    userPosition[_pid][msg.sender] -= _amount;
    reward[_pid][msg.sender] = 0;
  }

  function pendingReward(uint256 _pid, address _who) external view returns (uint256) {
    return reward[_pid][_who];
  }

  function setReward(
    uint256 _pid,
    address _who,
    uint256 _rewardAmount
  ) external {
    reward[_pid][_who] = _rewardAmount;
  }
}
