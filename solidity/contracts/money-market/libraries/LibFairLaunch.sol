// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libraries
import { LibMoneyMarket01 } from "./LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";

library LibFairLaunch {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function addIbTokenCollat(
    address _ibToken,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage ibTokenCollats = moneyMarketDs.accountIbTokenCollats[msg.sender];
    if (ibTokenCollats.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      ibTokenCollats.init();
    }

    uint256 _oldIbTokenCollat = ibTokenCollats.getAmount(_ibToken);
    moneyMarketDs.accountIbTokenCollats[msg.sender].addOrUpdate(_ibToken, _oldIbTokenCollat + _amount);
    // update reward debt
    LibMoneyMarket01.PoolInfo storage pool = updatePool(_ibToken, moneyMarketDs);
    uint256 _addRewardDebt = (_amount * pool.accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION;
    moneyMarketDs.accountRewardDebts[msg.sender][_ibToken] += _addRewardDebt;
  }

  function removeIbTokenCollat(
    address _ibToken,
    uint256 _removeAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    LibDoublyLinkedList.List storage ibTokenCollats = moneyMarketDs.accountIbTokenCollats[msg.sender];
    uint256 _oldIbTokenCollat = ibTokenCollats.getAmount(_ibToken);
    moneyMarketDs.accountIbTokenCollats[msg.sender].updateOrRemove(_ibToken, _oldIbTokenCollat - _removeAmount);
    // update reward debt
    LibMoneyMarket01.PoolInfo storage pool = updatePool(_ibToken, moneyMarketDs);
    uint256 _removeRewardDebt = (_removeAmount * pool.accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION;
    moneyMarketDs.accountRewardDebts[msg.sender][_ibToken] -= _removeRewardDebt;
  }

  function pendingReward(
    address _account,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _reward) {
    LibMoneyMarket01.PoolInfo storage poolInfo = moneyMarketDs.poolInfos[_token];
    uint256 _accRewardPerShare = poolInfo.accRewardPerShare;
    if (block.timestamp > poolInfo.lastRewardTime) {
      uint256 _tokenBalance = ERC20(_token).balanceOf(address(this));
      if (_tokenBalance > 0) {
        uint256 _timePast = block.timestamp - poolInfo.lastRewardTime;
        uint256 _alpacaReward = (_timePast * moneyMarketDs.rewardConfig.rewardPerSecond * poolInfo.allocPoint) /
          moneyMarketDs.totalAllocPoint;
        _accRewardPerShare += (_alpacaReward * LibMoneyMarket01.ACC_ALPACA_PRECISION) / _tokenBalance;
      }
    }
    LibDoublyLinkedList.List storage ibTokenCollats = moneyMarketDs.accountIbTokenCollats[_account];
    uint256 _collat = ibTokenCollats.getAmount(_token);
    uint256 _rewardDebt = moneyMarketDs.accountRewardDebts[_account][_token];
    _reward = ((_collat * _accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION) - _rewardDebt;
  }

  function updatePool(address _token, LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs)
    internal
    returns (LibMoneyMarket01.PoolInfo storage poolInfo)
  {
    poolInfo = moneyMarketDs.poolInfos[_token];
    if (block.timestamp > poolInfo.lastRewardTime) {
      uint256 _tokenBalance = ERC20(_token).balanceOf(address(this));
      if (_tokenBalance > 0) {
        uint256 _timePast = block.timestamp - poolInfo.lastRewardTime;
        uint256 _alpacaReward = (_timePast * moneyMarketDs.rewardConfig.rewardPerSecond * poolInfo.allocPoint) /
          moneyMarketDs.totalAllocPoint;
        poolInfo.accRewardPerShare += (_alpacaReward * LibMoneyMarket01.ACC_ALPACA_PRECISION) / _tokenBalance;
      }
      poolInfo.lastRewardTime = block.timestamp;
    }
  }
}
