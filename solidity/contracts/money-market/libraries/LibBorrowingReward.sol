// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libraries
import { LibMoneyMarket01 } from "./LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";

// interfaces
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

library LibBorrowingReward {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;
  using SafeCast for int256;

  error LibBorrowingReward_InvalidRewardToken();
  error LibBorrowingReward_InvalidRewardDistributor();

  function claim(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (address _rewardToken, uint256 _unclaimedReward) {
    _rewardToken = moneyMarketDs.rewardConfig.rewardToken;
    address _rewardDistributor = moneyMarketDs.rewardDistributor;

    if (_rewardToken == address(0)) revert LibBorrowingReward_InvalidRewardToken();
    if (_rewardDistributor == address(0)) revert LibBorrowingReward_InvalidRewardDistributor();

    LibMoneyMarket01.PoolInfo memory poolInfo = updatePool(_token, moneyMarketDs);
    uint256 _amount = moneyMarketDs.accountDebtShares[_account][_token];
    int256 _rewardDebt = moneyMarketDs.borrowerRewardDebts[_account][_token];

    int256 _accumulatedReward = ((_amount * poolInfo.accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION)
      .toInt256();
    _unclaimedReward = (_accumulatedReward - _rewardDebt).toUint256();

    moneyMarketDs.borrowerRewardDebts[_account][_token] = _accumulatedReward;

    if (_unclaimedReward > 0) {
      IRewardDistributor(_rewardDistributor).safeTransferReward(_rewardToken, _account, _unclaimedReward);
    }
  }

  function updateRewardDebt(
    address _account,
    address _token,
    int256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal {
    ds.borrowerRewardDebts[_account][_token] +=
      (_amount * ds.borrowingPoolInfos[_token].accRewardPerShare.toInt256()) /
      LibMoneyMarket01.ACC_REWARD_PRECISION.toInt256();
  }

  function pendingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _actualReward) {
    LibMoneyMarket01.PoolInfo storage poolInfo = moneyMarketDs.borrowingPoolInfos[_token];
    uint256 _accRewardPerShare = poolInfo.accRewardPerShare + _calculateRewardPerShare(_token, moneyMarketDs);
    uint256 _amount = moneyMarketDs.accountDebtShares[_account][_token];
    int256 _rewardDebt = moneyMarketDs.borrowerRewardDebts[_account][_token];
    int256 _accumulatedReward = ((_amount * _accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION).toInt256();
    _actualReward = (_accumulatedReward - _rewardDebt).toUint256();
  }

  function updatePool(address _token, LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    returns (LibMoneyMarket01.PoolInfo memory poolInfo)
  {
    moneyMarketDs.borrowingPoolInfos[_token].accRewardPerShare += _calculateRewardPerShare(_token, moneyMarketDs);
    moneyMarketDs.borrowingPoolInfos[_token].lastRewardTime = block.timestamp.toUint128();
    return moneyMarketDs.borrowingPoolInfos[_token];
  }

  function _calculateRewardPerShare(address _token, LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    view
    returns (uint256 _rewardPerShare)
  {
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.borrowingPoolInfos[_token];
    if (block.timestamp > poolInfo.lastRewardTime) {
      uint256 _tokenBalance = moneyMarketDs.debtShares[_token];
      if (_tokenBalance > 0) {
        uint256 _timePast = block.timestamp - poolInfo.lastRewardTime;
        uint256 _reward = (_timePast * moneyMarketDs.rewardConfig.rewardPerSecond * poolInfo.allocPoint) /
          moneyMarketDs.totalBorrowingPoolAllocPoint;
        _rewardPerShare = (_reward * LibMoneyMarket01.ACC_REWARD_PRECISION) / _tokenBalance;
      }
    }
  }
}
