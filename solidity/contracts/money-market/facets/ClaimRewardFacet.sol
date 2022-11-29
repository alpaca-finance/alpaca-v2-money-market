// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { IClaimRewardFacet } from "../interfaces/IClaimRewardFacet.sol";
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibFairLaunch } from "../libraries/LibFairLaunch.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

contract ClaimRewardFacet is IClaimRewardFacet {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // events
  event LogClaimReward(address indexed _to, address _rewardToken, uint256 _amount);

  // todo: nonreentrant
  function claimReward(address _token) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.PoolInfo storage poolInfo = LibFairLaunch.updatePool(_token, moneyMarketDs);
    LibDoublyLinkedList.List storage ibTokenCollats = moneyMarketDs.accountIbTokenCollats[msg.sender];
    uint256 _amount = ibTokenCollats.getAmount(_token);
    uint256 _rewardDebt = moneyMarketDs.accountRewardDebts[msg.sender][_token];

    uint256 _accumulatedReward = (_amount * poolInfo.accRewardPerShare) / LibMoneyMarket01.ACC_ALPACA_PRECISION;
    uint256 _pendingReward = _accumulatedReward - _rewardDebt;

    // todo: lib function
    moneyMarketDs.accountRewardDebts[msg.sender][_token] = _accumulatedReward;

    if (_pendingReward > 0) {
      IRewardDistributor(moneyMarketDs.rewardDistributor).safeTransferReward(
        moneyMarketDs.rewardToken,
        msg.sender,
        _pendingReward
      );
    }

    emit LogClaimReward(msg.sender, moneyMarketDs.rewardToken, _pendingReward);
  }

  function pendingReward(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibFairLaunch.pendingReward(msg.sender, _token, moneyMarketDs);
  }
}
