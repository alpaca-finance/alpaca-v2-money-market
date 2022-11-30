// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IRewardFacet } from "../interfaces/IRewardFacet.sol";
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibReward } from "../libraries/LibReward.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

contract RewardFacet is IRewardFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // events
  event LogClaimReward(address indexed _to, address _rewardToken, uint256 _amount);

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function claimReward(address _token) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    (address _rewardToken, uint256 _pendingReward) = LibReward.claimReward(msg.sender, _token, moneyMarketDs);

    emit LogClaimReward(msg.sender, _rewardToken, _pendingReward);
  }

  function pendingReward(address _account, address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibReward.pendingReward(_account, _token, moneyMarketDs);
  }

  function accountRewardDebts(address _account, address _token) external view returns (int256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.accountRewardDebts[_account][_token];
  }
}
