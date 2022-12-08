// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IRewardFacet } from "../interfaces/IRewardFacet.sol";
import { IRewardDistributor } from "../interfaces/IRewardDistributor.sol";

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibLendingReward } from "../libraries/LibLendingReward.sol";
import { LibBorrowingReward } from "../libraries/LibBorrowingReward.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

contract RewardFacet is IRewardFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // events
  event LogLendingClaimRewardFor(address indexed _claimFor, address _rewardToken, uint256 _amount);
  event LogClaimBorrowingRewardFor(address indexed _claimFor, address _rewardToken, uint256 _amount);

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function claimLendingRewardFor(
    address _claimFor,
    address _rewardToken,
    address _token
  ) external nonReentrant {
    _claimLendingRewardFor(_claimFor, _rewardToken, _token);
  }

  function claimMultipleLendingRewardsFor(
    address _claimFor,
    address[] calldata _rewardTokens,
    address[] calldata _tokens
  ) external nonReentrant {
    uint256 _rewardLength = _rewardTokens.length;
    uint256 _tokenLength = _tokens.length;
    for (uint256 _i; _i < _rewardLength; ) {
      for (uint256 _j; _j < _tokenLength; ) {
        _claimLendingRewardFor(_claimFor, _rewardTokens[_i], _tokens[_j]);
        unchecked {
          ++_j;
        }
      }
      unchecked {
        ++_i;
      }
    }
  }

  function _claimLendingRewardFor(
    address _claimFor,
    address _rewardToken,
    address _token
  ) internal {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _claimedReward = LibLendingReward.claimFor(_claimFor, _rewardToken, _token, moneyMarketDs);

    emit LogLendingClaimRewardFor(_claimFor, _rewardToken, _claimedReward);
  }

  function claimBorrowingRewardFor(
    address _claimFor,
    address _rewardToken,
    address _token
  ) external nonReentrant {
    _claimBorrowingRewardFor(_claimFor, _rewardToken, _token);
  }

  function claimMultipleBorrowingRewardsFor(
    address _claimFor,
    address[] calldata _rewardTokens,
    address[] calldata _tokens
  ) external nonReentrant {
    uint256 _rewardLength = _rewardTokens.length;
    uint256 _tokenLength = _tokens.length;
    for (uint256 _i; _i < _rewardLength; ) {
      for (uint256 _j; _j < _tokenLength; ) {
        _claimBorrowingRewardFor(_claimFor, _rewardTokens[_i], _tokens[_j]);
        unchecked {
          ++_j;
        }
      }
      unchecked {
        ++_i;
      }
    }
  }

  function _claimBorrowingRewardFor(
    address _claimFor,
    address _rewardToken,
    address _token
  ) internal {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _claimedReward = LibBorrowingReward.claimFor(_claimFor, _rewardToken, _token, moneyMarketDs);

    emit LogClaimBorrowingRewardFor(_claimFor, _rewardToken, _claimedReward);
  }

  function pendingLendingReward(
    address _account,
    address _rewardToken,
    address _token
  ) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibLendingReward.pendingReward(_account, _rewardToken, _token, moneyMarketDs);
  }

  function pendingBorrowingReward(
    address _account,
    address _rewardToken,
    address _token
  ) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibBorrowingReward.pendingReward(_account, _rewardToken, _token, moneyMarketDs);
  }

  function lenderRewardDebts(
    address _account,
    address _rewardToken,
    address _token
  ) external view returns (int256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    return moneyMarketDs.lenderRewardDebts[_account][_poolKey];
  }

  function borrowerRewardDebts(
    address _account,
    address _rewardToken,
    address _token
  ) external view returns (int256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    return moneyMarketDs.borrowerRewardDebts[_account][_poolKey];
  }

  function getLendingPool(address _rewardToken, address _token)
    external
    view
    returns (LibMoneyMarket01.PoolInfo memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.lendingPoolInfos[LibMoneyMarket01.getPoolKey(_rewardToken, _token)];
  }

  function getBorrowingPool(address _rewardToken, address _token)
    external
    view
    returns (LibMoneyMarket01.PoolInfo memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.borrowingPoolInfos[LibMoneyMarket01.getPoolKey(_rewardToken, _token)];
  }
}
