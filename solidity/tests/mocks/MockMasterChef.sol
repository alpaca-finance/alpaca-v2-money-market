// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { IMasterChefLike } from "../../contracts/lyf/interfaces/IMasterChefLike.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockMasterChef is IMasterChefLike {
  struct PoolInfo {
    address lpAddress;
    uint256 poolId;
  }

  struct UserInfo {
    uint256 amount; // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
  }

  mapping(uint256 => PoolInfo) poolInfo;

  // Info of each user that stakes LP tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  mapping(uint256 => mapping(address => uint256)) reward;
  address rewardToken;

  constructor(address _rewardToken) {
    rewardToken = _rewardToken;
  }

  function addLendingPool(address _lpAddress, uint256 _pid) external {
    poolInfo[_pid] = PoolInfo({ lpAddress: _lpAddress, poolId: _pid });
  }

  function deposit(uint256 _pid, uint256 _amount) external {
    ERC20(poolInfo[_pid].lpAddress).transferFrom(msg.sender, address(this), _amount);
    userInfo[_pid][msg.sender].amount += _amount;
  }

  function withdraw(uint256 _pid, uint256 _amount) external {
    ERC20(poolInfo[_pid].lpAddress).transfer(msg.sender, _amount);

    uint256 _rewardAmount = reward[_pid][msg.sender];

    userInfo[_pid][msg.sender].amount -= _amount;
    reward[_pid][msg.sender] = 0;

    ERC20(rewardToken).transfer(msg.sender, _rewardAmount);
  }

  function pendingReward(uint256 _pid, address _who) external view returns (uint256) {
    return reward[_pid][_who];
  }

  function setReward(
    uint256 _pid,
    address _who,
    uint256 _rewardAmount
  ) external {
    ERC20(rewardToken).transferFrom(msg.sender, address(this), _rewardAmount);
    reward[_pid][_who] = _rewardAmount;
  }
}
