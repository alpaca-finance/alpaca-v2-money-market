// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libraries
import { LibMoneyMarket01 } from "./LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";

// interfaces
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

library LibReward {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  error LibReward_InvalidRewardToken();
  error LibReward_InvalidRewardDistributor();

  function claimReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (address _rewardToken, uint256 _unclaimedReward) {
    _rewardToken = moneyMarketDs.rewardConfig.rewardToken;
    address _rewardDistributor = moneyMarketDs.rewardDistributor;

    if (_rewardToken == address(0)) revert LibReward_InvalidRewardToken();
    if (_rewardDistributor == address(0)) revert LibReward_InvalidRewardDistributor();

    LibMoneyMarket01.PoolInfo memory poolInfo = updatePool(_token, moneyMarketDs);
    LibDoublyLinkedList.List storage accountCollatsList = moneyMarketDs.accountCollats[_account];
    uint256 _amount = accountCollatsList.getAmount(_token);
    uint256 _rewardDebt = moneyMarketDs.accountRewardDebts[_account][_token];

    uint256 _accumulatedReward = (_amount * poolInfo.accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION;
    _unclaimedReward = _accumulatedReward - _rewardDebt;

    moneyMarketDs.accountRewardDebts[_account][_token] = _accumulatedReward;

    if (_unclaimedReward > 0) {
      IRewardDistributor(_rewardDistributor).safeTransferReward(_rewardToken, _account, _unclaimedReward);
    }
  }

  function pendingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _reward) {
    LibMoneyMarket01.PoolInfo storage poolInfo = moneyMarketDs.poolInfos[_token];
    uint256 _accRewardPerShare = poolInfo.accRewardPerShare + _calculateAccRewardPerShare(_token, moneyMarketDs);

    LibDoublyLinkedList.List storage accountCollatsList = moneyMarketDs.accountCollats[_account];
    uint256 _amount = accountCollatsList.getAmount(_token);
    uint256 _rewardDebt = moneyMarketDs.accountRewardDebts[_account][_token];
    _reward = ((_amount * _accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION) - _rewardDebt;
  }

  function updatePool(address _token, LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (LibMoneyMarket01.PoolInfo memory poolInfo)
  {
    poolInfo = moneyMarketDs.poolInfos[_token];
    poolInfo.accRewardPerShare += _calculateAccRewardPerShare(_token, moneyMarketDs);
  }

  function _calculateAccRewardPerShare(address _token, LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _newAccRewardPerShare)
  {
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.poolInfos[_token];
    if (block.timestamp > poolInfo.lastRewardTime) {
      uint256 _tokenBalance = ERC20(_token).balanceOf(address(this));
      if (_tokenBalance > 0) {
        uint256 _timePast = block.timestamp - poolInfo.lastRewardTime;
        uint256 _alpacaReward = (_timePast * moneyMarketDs.rewardConfig.rewardPerSecond * poolInfo.allocPoint) /
          moneyMarketDs.totalAllocPoint;
        _newAccRewardPerShare = (_alpacaReward * LibMoneyMarket01.ACC_ALPACA_PRECISION) / _tokenBalance;
      }
    }
  }
}
