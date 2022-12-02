// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IRewardDistributor } from "./interfaces/IRewardDistributor.sol";

contract RewardDistributor is IRewardDistributor, Ownable {
  using SafeERC20 for ERC20;

  mapping(address => bool) public callersOk;

  function safeTransferReward(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyWhitelisted {
    ERC20 _rewardToken = ERC20(_token);
    if (_rewardToken.balanceOf(address(this)) < _amount) revert RewardDistributor_InsufficientBalance();
    _rewardToken.safeTransfer(_to, _amount);

    emit LogSafeTransferReward(_token, msg.sender, _to, _amount);
  }

  function setCallersOk(address[] calldata _callers, bool isOk) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint8 _i; _i < _length; ) {
      callersOk[_callers[_i]] = isOk;
      unchecked {
        _i++;
      }
    }
  }

  modifier onlyWhitelisted() {
    if (!callersOk[msg.sender]) revert RewardDistributor_Unauthorized(msg.sender);
    _;
  }
}
