// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { console } from "../utils/console.sol";

contract MoneyMarket_LendingRewardTest is MoneyMarket_BaseTest {
  using SafeCast for uint256;
  using SafeCast for int256;

  function setUp() public override {
    super.setUp();

    // mint ib token for users
    ibWeth.mint(ALICE, 20 ether);
    ibWeth.mint(BOB, 20 ether);
    ibUsdc.mint(ALICE, 5 ether);
  }

  function testCorrectness_WhenAdminSetLendingRewardPerSec_PoolAccRewardPerShareShouldBeUpdatedCorrectly() external {
    _addIbTokenAsCollateral(ALICE, address(ibWeth), 10 ether);
    vm.warp(block.timestamp + 100);
    adminFacet.updateLendingRewardPerSec(address(rewardToken), 3 ether);
    assertEq(rewardFacet.getLendingPool(address(rewardToken), address(ibWeth)).accRewardPerShare, 2e12);
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
    _claimReward(ALICE, address(rewardToken), _ibToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(ALICE, address(rewardToken), _ibToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);
  }

  function testCorrectness_WhenUserAddCollateralAndClaimMultipleReward_UserShouldReceivedRewardCorrectly() external {
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
    _claimReward(ALICE, address(rewardToken), _ibToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(ALICE, address(rewardToken), _ibToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    // add new reward for this token
    adminFacet.addLendingRewardPerSec(address(rewardToken2), 0.5 ether);
    adminFacet.addLendingPool(address(rewardToken2), address(ibWeth), 20);
    adminFacet.addLendingPool(address(rewardToken2), address(ibBtc), 80);
    vm.warp(block.timestamp + 100);

    _claimReward(ALICE, address(rewardToken), _ibToken);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 0.5 ether,  total alloc point is 100
    // then reward = 100 * 0.5 * 20 / 100 = 10 ether
    // then acc reward per share = 10 ether / 10 ether (total of collat token) = 1 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 1) - 0 = 10 (precision is 12)
    _claimReward(ALICE, address(rewardToken2), _ibToken);

    _assertAccountReward(ALICE, address(rewardToken), _ibToken, 40 ether, 40 ether);
    _assertAccountReward(ALICE, address(rewardToken2), _ibToken, 10 ether, 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - 40 ether);
    assertEq(rewardToken2.balanceOf(address(rewardDistributor)), 1000000 ether - 10 ether);
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
    _claimReward(ALICE, address(rewardToken), _ibToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(ALICE, address(rewardToken), _ibToken, _expectedReward, _expectedReward.toInt256());
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
    _assertAccountReward(
      ALICE,
      address(rewardToken),
      _ibToken,
      _expectedReward,
      -_expectedRewardAfterRemove.toInt256()
    );
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    _claimReward(ALICE, address(rewardToken), _ibToken);
    _assertAccountReward(ALICE, address(rewardToken), _ibToken, _expectedReward + _expectedRewardAfterRemove, 0 ether);
    assertEq(
      rewardToken.balanceOf(address(rewardDistributor)),
      1000000 ether - (_expectedReward + _expectedRewardAfterRemove)
    );
  }

  function testCorrectness_WhenMultipleAddCollateralInSamePoolInDifferentTimeAndClaim_AllUsersShouldReceiveRewardCorrectly()
    external
  {
    address _collatToken = address(ibWeth);

    uint256 _aliceCollat = 10 ether;
    uint256 _bobCollat = 20 ether;

    _addIbTokenAsCollateral(ALICE, _collatToken, _aliceCollat);
    assertEq(collateralFacet.accountCollats(ALICE, _collatToken), _aliceCollat);

    uint256 _bobAddCollatTimestamp = block.timestamp + 100;
    vm.warp(_bobAddCollatTimestamp);

    _addIbTokenAsCollateral(BOB, _collatToken, _bobCollat);
    // bob reward debt should be calculated
    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token before bob add collats) = 2 (precision is 12)
    // reward debt should be update to 20 * 2 = 40
    int256 _bobRewardDebtToUpdate = 40 ether;
    assertEq(collateralFacet.accountCollats(BOB, _collatToken), _bobCollat);
    assertEq(rewardFacet.lenderRewardDebts(BOB, address(rewardToken), _collatToken), _bobRewardDebtToUpdate);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(_bobAddCollatTimestamp + 100);

    // ibWeth pool alloc point is 20
    // given time past 200 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 30 ether (total of collat token) = 0.666666666666 (precision is 12)
    // then total acc reward per share = 2 (old) + 0.666666666666 = 2.666666666666
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (10 * 2.666666666666) - 0 = 26.666666666660 (precision is 12)
    // bob reward debt is 40 now, then unclaimed reward = (20 * 2.666666666666 = 53.333333333320) - 40 = 13.333333333320 (precision is 12)
    _claimReward(ALICE, address(rewardToken), _collatToken);
    _claimReward(BOB, address(rewardToken), _collatToken);

    uint256 _expectedAliceReward = 26.66666666666 ether;
    uint256 _expectedBobReward = 13.33333333332 ether;
    _assertAccountReward(
      ALICE,
      address(rewardToken),
      _collatToken,
      _expectedAliceReward,
      _expectedAliceReward.toInt256()
    );
    _assertAccountReward(
      BOB,
      address(rewardToken),
      _collatToken,
      _expectedBobReward,
      _bobRewardDebtToUpdate + _expectedBobReward.toInt256()
    );

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
    _claimReward(ALICE, address(rewardToken), _ibToken1);
    _assertAccountReward(ALICE, address(rewardToken), _ibToken1, _expectedReward1, _expectedReward1.toInt256());

    // ibUsdc pool alloc point is 40
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 40 / 100 = 40 ether
    // then acc reward per share = 40 ether / 5 ether (total of collat token) = 8 (precision is 12)
    // formula of unclaimed reward = (collat amount * acc reward per share) - reward debt
    // alice reward debt is 0 now, then unclaimed reward = (5 * 8) - 0 = 40 (precision is 12)
    uint256 _expectedReward2 = 40 ether;
    _claimReward(ALICE, address(rewardToken), _ibToken2);

    // total of claimed reward = 20 + 40 = 60
    // but reward debt fot ibToken2 should be 40
    _assertAccountReward(
      ALICE,
      address(rewardToken),
      _ibToken2,
      _expectedReward1 + _expectedReward2,
      _expectedReward2.toInt256()
    );

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
    _claimReward(ALICE, address(rewardToken), _ibToken);

    uint256 _expectedFirstReward = 20 ether;

    _assertAccountReward(ALICE, address(rewardToken), _ibToken, _expectedFirstReward, _expectedFirstReward.toInt256());
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
      rewardFacet.lenderRewardDebts(ALICE, address(rewardToken), _ibToken),
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
    _claimReward(ALICE, address(rewardToken), _ibToken);

    _assertAccountReward(
      ALICE,
      address(rewardToken),
      _ibToken,
      _totalReward,
      _totalReward.toInt256() + _expectRewardDebtToUpdate
    );
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

  function _claimReward(
    address _account,
    address _rewardToken,
    address _collatToken
  ) internal {
    rewardFacet.claimLendingRewardFor(_account, _rewardToken, _collatToken);
  }

  function _assertAccountReward(
    address _account,
    address _rewardToken,
    address _collatToken,
    uint256 _claimedReward,
    int256 _rewardDebt
  ) internal {
    assertEq(MockERC20(_rewardToken).balanceOf(_account), _claimedReward);
    assertEq(rewardFacet.lenderRewardDebts(_account, _rewardToken, _collatToken), _rewardDebt);
  }
}
