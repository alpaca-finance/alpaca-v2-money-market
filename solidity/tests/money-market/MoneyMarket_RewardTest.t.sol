// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { console } from "../utils/console.sol";

contract MoneyMarket_RewardTest is MoneyMarket_BaseTest {
  using SafeCast for uint256;
  using SafeCast for int256;

  function setUp() public override {
    super.setUp();

    // mint ib token for users
    ibWeth.mint(ALICE, 20 ether);
    ibWeth.mint(BOB, 20 ether);
    ibUsdc.mint(ALICE, 5 ether);
  }

  function testCorrectness_WhenUserAddCollateralAndClaimReward_UserShouldReceivedRewardCorrectly() external {
    address _ibToken = address(ibWeth);
    _addIbTokenAsCollateral(ALICE, _ibToken, 10 ether);

    assertEq(collateralFacet.accountCollats(ALICE, _ibToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token) = 2 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    _claimReward(ALICE, _ibToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(ALICE, _ibToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);
  }

  function testCorrectness_WhenUserAddCollateralAndClaimRewardAndRemoveCollat_UserShouldReceivedRewardCorrectly()
    external
  {
    address _ibToken = address(ibWeth);
    _addIbTokenAsCollateral(ALICE, _ibToken, 10 ether);

    assertEq(collateralFacet.accountCollats(ALICE, _ibToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    uint256 _claimTimestamp = block.timestamp + 100;
    vm.warp(_claimTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token) = 2 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    _claimReward(ALICE, _ibToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(ALICE, _ibToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    uint256 _removeTimestamp = _claimTimestamp + 100;
    vm.warp(_removeTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then new acc reward per share = (2) + 20 ether / 10 ether (total of collat token) = 4 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 20 from first claim, then unclaimed reward = (10 * 4) - 20 = 20 (precision is 12)
    uint256 _expectedRewardAfterRemove = 20 ether;

    _removeIbTokenCollateral(ALICE, _ibToken, 10 ether);
    _assertAccountReward(ALICE, _ibToken, _expectedReward, -_expectedRewardAfterRemove.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    _claimReward(ALICE, _ibToken);
    _assertAccountReward(ALICE, _ibToken, _expectedReward + _expectedRewardAfterRemove, 0 ether);
    assertEq(
      rewardToken.balanceOf(address(rewardDistributor)),
      1000000 ether - (_expectedReward + _expectedRewardAfterRemove)
    );
  }

  function testCorrectness_WhenMultipleAddCollateralInSamePoolAndClaim_AllUsersShouldReceiveRewardCorrectly() external {
    address _aliceIbToken = address(ibWeth);
    address _bobIbToken = address(ibWeth);

    uint256 _aliceCollat = 10 ether;
    uint256 _bobCollat = 20 ether;

    _addIbTokenAsCollateral(ALICE, _aliceIbToken, _aliceCollat);
    _addIbTokenAsCollateral(BOB, _bobIbToken, _bobCollat);

    assertEq(collateralFacet.accountCollats(ALICE, _aliceIbToken), _aliceCollat);
    assertEq(collateralFacet.accountCollats(BOB, _aliceIbToken), _bobCollat);

    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    _claimReward(ALICE, _aliceIbToken);
    _claimReward(BOB, _bobIbToken);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 30 ether (total of collat token) = 0.666666666666 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 0.666666666666) - 0 = 6.666666666660 (precision is 12)
    // bob reward debt is 0 now, then unclaimed reward = (20 * 0.666666666666) - 0 = 13.333333333320 (precision is 12)
    uint256 _expectedAliceReward = 6.66666666666 ether;
    uint256 _expectedBobReward = 13.33333333332 ether;
    _assertAccountReward(ALICE, _aliceIbToken, _expectedAliceReward, _expectedAliceReward.toInt256());
    _assertAccountReward(BOB, _bobIbToken, _expectedBobReward, _expectedBobReward.toInt256());

    assertEq(
      rewardToken.balanceOf(address(rewardDistributor)),
      1000000 ether - (_expectedAliceReward + _expectedBobReward)
    );
  }

  function testCorrectness_WhenUserAddMultipleCollateralAndClaimReward_UserShouldReceivedRewardCorrectly() external {
    address _ibToken1 = address(ibWeth);
    address _ibToken2 = address(ibUsdc);
    _addIbTokenAsCollateral(ALICE, _ibToken1, 10 ether);
    _addIbTokenAsCollateral(ALICE, _ibToken2, 5 ether);

    assertEq(collateralFacet.accountCollats(ALICE, _ibToken1), 10 ether);
    assertEq(collateralFacet.accountCollats(ALICE, _ibToken2), 5 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token) = 2 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    uint256 _expectedReward1 = 20 ether;
    _claimReward(ALICE, _ibToken1);
    _assertAccountReward(ALICE, _ibToken1, _expectedReward1, _expectedReward1.toInt256());

    // ibUsdc pool alloc point is 40
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 40 / 100 = 40 ether
    // then acc reward per share = 40 ether / 5 ether (total of collat token) = 8 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (5 * 8) - 0 = 40 (precision is 12)
    uint256 _expectedReward2 = 40 ether;
    _claimReward(ALICE, _ibToken2);

    // total of claimed reward = 20 + 40 = 60
    // but reward debt fot ibToken2 should be 40
    _assertAccountReward(ALICE, _ibToken2, _expectedReward1 + _expectedReward2, _expectedReward2.toInt256());

    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - (_expectedReward1 + _expectedReward2));
  }

  function testCorrectness_WhenUserAddCollatAndClaimTwice_UserShouldReceivedRewardCorreclty() external {
    address _ibToken = address(ibWeth);
    _addIbTokenAsCollateral(ALICE, _ibToken, 10 ether);

    assertEq(collateralFacet.accountCollats(ALICE, _ibToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    uint256 _firstClaimTimestamp = block.timestamp + 100;
    vm.warp(_firstClaimTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token) = 2 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    _claimReward(ALICE, _ibToken);

    uint256 _expectedFirstReward = 20 ether;

    _assertAccountReward(ALICE, _ibToken, _expectedFirstReward, _expectedFirstReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedFirstReward);
    uint256 _secondAddCollatTimestamp = _firstClaimTimestamp + 100;
    vm.warp(_secondAddCollatTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token) = 2 (precision is 12)
    // then total acc reward per share = 2 (old) + 2 = 4
    // reward debt should be update to 10 * 4 = 40 + 20 (claimed amount before)
    int256 _expectRewardDebtToUpdate = 40 ether;
    _addIbTokenAsCollateral(ALICE, _ibToken, 10 ether);

    assertEq(collateralFacet.accountCollats(ALICE, _ibToken), 20 ether);
    assertEq(
      RewardFacet.accountRewardDebts(ALICE, _ibToken),
      _expectRewardDebtToUpdate + _expectedFirstReward.toInt256()
    );
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedFirstReward);

    uint256 _secondClaimTimestamp = _secondAddCollatTimestamp + 100;
    vm.warp(_secondClaimTimestamp);

    // second claim
    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 20 ether (total of collat token) = 2 (precision is 12)
    // then total acc reward per share = 4 (old) + 1 = 5
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 60 now, then unclaimed reward = (10 * 5) - 60 = 40 (precision is 12)
    uint256 _expectedSecondReward = 40 ether;
    uint256 _totalReward = _expectedFirstReward + _expectedSecondReward;
    _claimReward(ALICE, _ibToken);

    _assertAccountReward(ALICE, _ibToken, _totalReward, _totalReward.toInt256() + _expectRewardDebtToUpdate);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _totalReward);
  }

  function _addIbTokenAsCollateral(
    address _account,
    address _collatToken,
    uint256 _amount
  ) internal {
    vm.startPrank(_account);
    MockERC20(_collatToken).approve(moneyMarketDiamond, _amount);
    collateralFacet.addCollateral(_account, 0, _collatToken, _amount);
    vm.stopPrank();
  }

  function _removeIbTokenCollateral(
    address _account,
    address _collatToken,
    uint256 _amount
  ) internal {
    vm.prank(_account);
    collateralFacet.removeCollateral(0, _collatToken, _amount);
  }

  function _claimReward(address _account, address _collatToken) internal {
    vm.prank(_account);
    rewardFacet.claimReward(_collatToken);
  }

  function _assertAccountReward(
    address _account,
    address _collatToken,
    uint256 _claimedReward,
    int256 _rewardDebt
  ) internal {
    assertEq(rewardFacet.accountRewardDebts(_account, _collatToken), _rewardDebt);
    assertEq(rewardToken.balanceOf(_account), _claimedReward);
  }
}
