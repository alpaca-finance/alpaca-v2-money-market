// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libraries
import { LibMoneyMarket01 } from "./LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";

// interfaces
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

import { console } from "../../../tests/utils/console.sol";

library LibReward02 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;
  using SafeCast for int256;

  error LibReward_InvalidRewardToken();
  error LibReward_InvalidRewardDistributor();

  function claimLendingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal returns (address _rewardToken, uint256 _toClaimReward) {
    _rewardToken = ds.rewardConfig.rewardToken;
    address _rewardDistributor = ds.rewardDistributor;

    _preClaim(_rewardToken, _rewardDistributor);

    LibMoneyMarket01.PoolInfo storage poolInfo = ds.poolInfos[_token];
    updatePool(poolInfo, ds.collats[_token], ds);

    uint256 _amount = ds.accountCollats[_account][_token];
    int256 _rewardDebt = ds.accountRewardDebts[_account][_token];

    int256 _accumulatedReward = ((_amount * poolInfo.accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION)
      .toInt256();
    _toClaimReward = (_accumulatedReward - _rewardDebt).toUint256();

    ds.accountRewardDebts[_account][_token] = _accumulatedReward;

    if (_toClaimReward > 0) {
      IRewardDistributor(_rewardDistributor).safeTransferReward(_rewardToken, _account, _toClaimReward);
    }
  }

  function claimBorrowingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal returns (address _rewardToken, uint256 _toClaimReward) {
    _rewardToken = ds.rewardConfig.rewardToken;
    address _rewardDistributor = ds.rewardDistributor;

    _preClaim(_rewardToken, _rewardDistributor);

    LibMoneyMarket01.PoolInfo storage poolInfo = ds.borrowerPoolInfos[_token];
    updatePool(poolInfo, ds.debtShares[_token], ds);

    uint256 _amount = ds.accountDebtShares[_account][_token];
    int256 _rewardDebt = ds.borrowerRewardDebts[_account][_token];

    int256 _accumulatedReward = ((_amount * poolInfo.accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION)
      .toInt256();
    _toClaimReward = (_accumulatedReward - _rewardDebt).toUint256();

    ds.borrowerRewardDebts[_account][_token] = _accumulatedReward;

    if (_toClaimReward > 0) {
      IRewardDistributor(_rewardDistributor).safeTransferReward(_rewardToken, _account, _toClaimReward);
    }
  }

  function updatePool(
    LibMoneyMarket01.PoolInfo storage poolInfo,
    uint256 _tokenBalance,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal {
    poolInfo.accRewardPerShare += _calculateAccRewardPerShare(poolInfo, _tokenBalance, ds);
    poolInfo.lastRewardTime = block.timestamp.toUint128();
  }

  function pendingLendingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal view returns (uint256 _actualReward) {
    LibMoneyMarket01.PoolInfo storage poolInfo = ds.poolInfos[_token];
    uint256 _accRewardPerShare = poolInfo.accRewardPerShare +
      _calculateAccRewardPerShare(poolInfo, ds.collats[_token], ds);
    uint256 _amount = ds.accountCollats[_account][_token];
    int256 _rewardDebt = ds.accountRewardDebts[_account][_token];
    int256 _reward = ((_amount * _accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION).toInt256();
    _actualReward = (_reward - _rewardDebt).toUint256();
  }

  function pendingBorrowingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal view returns (uint256 _actualReward) {
    LibMoneyMarket01.PoolInfo storage poolInfo = ds.poolInfos[_token];
    uint256 _accRewardPerShare = poolInfo.accRewardPerShare +
      _calculateAccRewardPerShare(poolInfo, ds.debtShares[_token], ds);
    uint256 _amount = ds.accountDebtShares[_account][_token];
    int256 _rewardDebt = ds.borrowerRewardDebts[_account][_token];
    int256 _reward = ((_amount * _accRewardPerShare) / LibMoneyMarket01.ACC_REWARD_PRECISION).toInt256();
    _actualReward = (_reward - _rewardDebt).toUint256();
  }

  function updateRewardDebt(
    address _account,
    address _token,
    int256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal {
    if (ds.poolInfos[_token].allocPoint > 0) {
      ds.accountRewardDebts[_account][_token] += _calculateRewardDebt(_amount, ds.poolInfos[_token].accRewardPerShare);
    }
  }

  function updateBorrowerRewardDebt(
    address _account,
    address _token,
    int256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal {
    if (ds.borrowerPoolInfos[_token].allocPoint > 0) {
      ds.borrowerRewardDebts[_account][_token] += _calculateRewardDebt(
        _amount,
        ds.borrowerPoolInfos[_token].accRewardPerShare
      );
    }
  }

  function _preClaim(address _rewardToken, address _rewardDistributor) internal pure {
    if (_rewardToken == address(0)) revert LibReward_InvalidRewardToken();
    if (_rewardDistributor == address(0)) revert LibReward_InvalidRewardDistributor();
  }

  function _calculateAccRewardPerShare(
    LibMoneyMarket01.PoolInfo storage poolInfo,
    uint256 _tokenBalance,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage ds
  ) internal view returns (uint256 _newAccRewardPerShare) {
    if (block.timestamp > poolInfo.lastRewardTime) {
      if (_tokenBalance > 0) {
        uint256 _timePast = block.timestamp - poolInfo.lastRewardTime;
        uint256 _reward = (_timePast * ds.rewardConfig.rewardPerSecond * poolInfo.allocPoint) / ds.totalAllocPoint;
        _newAccRewardPerShare = (_reward * LibMoneyMarket01.ACC_REWARD_PRECISION) / _tokenBalance;
      }
    }
  }

  function _calculateRewardDebt(int256 _amount, uint256 accRewardPerShare) internal pure returns (int256) {
    return (_amount * accRewardPerShare.toInt256()) / LibMoneyMarket01.ACC_REWARD_PRECISION.toInt256();
  }
}
