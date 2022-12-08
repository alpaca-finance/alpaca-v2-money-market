// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { console } from "../utils/console.sol";

contract MoneyMarket_BorrowingRewardTest is MoneyMarket_BaseTest {
  using SafeCast for uint256;
  using SafeCast for int256;

  function setUp() public override {
    super.setUp();

    // mint ib token for users
    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(btc), 50 ether);
    lendFacet.deposit(address(usdc), 50 ether);
    vm.stopPrank();

    vm.prank(BOB);
    collateralFacet.addCollateral(BOB, 0, address(btc), 80 ether);
  }

  function testCorrectness_WhenUserBorrowTokenAndClaimReward_UserShouldReceivedRewardCorrectly() external {
    address borrowedToken = address(weth);
    vm.prank(BOB);
    borrowFacet.borrow(0, address(weth), 10 ether);

    assertEq(borrowFacet.accountDebtShares(BOB, borrowedToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    // weth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of borrowed token) = 2 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    rewardFacet.claimBorrowingRewardFor(BOB, borrowedToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(BOB, borrowedToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);
  }

  function testCorrectness_WhenUserBorrowTokenAndClaimRewardThenRepayDebtAndClaimAgain_UserShouldReceivedRewardCorrectly()
    external
  {
    address borrowedToken = address(weth);
    vm.prank(BOB);
    borrowFacet.borrow(0, address(weth), 10 ether);

    assertEq(borrowFacet.accountDebtShares(BOB, borrowedToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    uint256 _claimTimestamp = block.timestamp + 100;
    vm.warp(_claimTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of borrowed token) = 2 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    rewardFacet.claimBorrowingRewardFor(BOB, borrowedToken);

    uint256 _expectedReward = 20 ether;

    _assertAccountReward(BOB, borrowedToken, _expectedReward, _expectedReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    uint256 _repayTimestamp = _claimTimestamp + 100;
    vm.warp(_repayTimestamp);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then new acc reward per share = (2) + 20 ether / 10 ether (total of borrowed token) = 4 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 20 from first claim, then unclaimed reward = (10 * 4) - 20 = 20 (precision is 12)
    uint256 _expectedRewardAfterRemove = 20 ether;

    vm.prank(BOB);
    borrowFacet.repay(BOB, 0, borrowedToken, 10 ether);
    _assertAccountReward(BOB, borrowedToken, _expectedReward, -_expectedRewardAfterRemove.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedReward);

    rewardFacet.claimBorrowingRewardFor(BOB, borrowedToken);
    _assertAccountReward(BOB, borrowedToken, _expectedReward + _expectedRewardAfterRemove, 0 ether);
    assertEq(
      rewardToken.balanceOf(address(rewardDistributor)),
      1000000 ether - (_expectedReward + _expectedRewardAfterRemove)
    );
  }

  function testCorrectness_WhenMultipleBorrowTokenInSamePoolAndClaim_AllUsersShouldReceiveRewardCorrectly() external {
    address _borrowedToken = address(weth);

    uint256 _bobBorrowedAmount = 10 ether;
    uint256 _eveBorrowedAmount = 10 ether;

    vm.prank(BOB);
    borrowFacet.borrow(0, _borrowedToken, _bobBorrowedAmount);
    assertEq(borrowFacet.accountDebtShares(BOB, _borrowedToken), _bobBorrowedAmount);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);

    uint256 _eveAddCollatTimestamp = block.timestamp + 100;
    vm.warp(_eveAddCollatTimestamp);

    vm.startPrank(DEPLOYER);
    chainLinkOracle.add(address(weth), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(usdc), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(isolateToken), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(btc), address(usd), 10 ether, block.timestamp);
    vm.stopPrank();

    vm.startPrank(EVE);
    btc.approve(moneyMarketDiamond, 50 ether);
    collateralFacet.addCollateral(EVE, 0, address(btc), 10 ether);
    borrowFacet.borrow(0, address(weth), _eveBorrowedAmount);
    vm.stopPrank();
    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of collat token before eve add collats) = 2 (precision is 12)
    // reward debt should be update to 10 * 2 = 20
    int256 _eveRewardDebtToUpdate = 20 ether;
    assertEq(borrowFacet.accountDebtShares(EVE, _borrowedToken), _eveBorrowedAmount);
    assertEq(rewardFacet.borrowerRewardDebts(EVE, _borrowedToken), _eveRewardDebtToUpdate);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(_eveAddCollatTimestamp + 100);

    rewardFacet.claimBorrowingRewardFor(BOB, _borrowedToken);
    rewardFacet.claimBorrowingRewardFor(EVE, _borrowedToken);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 20 ether (total of borrowed token) = 1 (precision is 12)
    // then total acc reward per share = 2 (old) + 1 = 3
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (10 * 3) - 0 = 30 (precision is 12)
    // eve reward debt is 20 now, then unclaimed reward = (10 * 3) - 20 = 10 (precision is 12)
    uint256 _expectedBobReward = 30 ether;
    uint256 _expectedEveReward = 10 ether;
    _assertAccountReward(BOB, _borrowedToken, _expectedBobReward, _expectedBobReward.toInt256());
    _assertAccountReward(
      EVE,
      _borrowedToken,
      _expectedEveReward,
      _eveRewardDebtToUpdate + _expectedEveReward.toInt256()
    );

    assertEq(
      rewardToken.balanceOf(address(rewardDistributor)),
      1000000 ether - (_expectedEveReward + _expectedBobReward)
    );
  }

  function testCorrectness_WhenUserBorrowMultipleTokenAndClaimReward_UserShouldReceivedRewardCorrectly() external {
    address _borrowedToken1 = address(weth);
    address _borrowedToken2 = address(usdc);

    vm.startPrank(BOB);
    borrowFacet.borrow(0, _borrowedToken1, 10 ether);
    borrowFacet.borrow(0, _borrowedToken2, 5 ether);

    assertEq(borrowFacet.accountDebtShares(BOB, _borrowedToken1), 10 ether);
    assertEq(borrowFacet.accountDebtShares(BOB, _borrowedToken2), 5 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    vm.warp(block.timestamp + 100);

    // ibWeth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of borrowed token) = 2 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    uint256 _expectedReward1 = 20 ether;
    rewardFacet.claimBorrowingRewardFor(BOB, _borrowedToken1);
    _assertAccountReward(BOB, _borrowedToken1, _expectedReward1, _expectedReward1.toInt256());

    // ibUsdc pool alloc point is 40
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 40 / 100 = 40 ether
    // then acc reward per share = 40 ether / 5 ether (total of borrowed token) = 8 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (5 * 8) - 0 = 40 (precision is 12)
    uint256 _expectedReward2 = 40 ether;
    rewardFacet.claimBorrowingRewardFor(BOB, _borrowedToken2);

    // total of claimed reward = 20 + 40 = 60
    // but reward debt fot ibToken2 should be 40
    _assertAccountReward(BOB, _borrowedToken2, _expectedReward1 + _expectedReward2, _expectedReward2.toInt256());

    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - (_expectedReward1 + _expectedReward2));
  }

  function testCorrectness_WhenUserBorrowTokenAndClaimRewardTwice_UserShouldReceivedRewardCorrectly() external {
    address borrowedToken = address(weth);
    vm.prank(BOB);
    borrowFacet.borrow(0, address(weth), 10 ether);

    assertEq(borrowFacet.accountDebtShares(BOB, borrowedToken), 10 ether);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether);
    uint256 _firstClaimTimestamp = block.timestamp + 100;
    vm.warp(_firstClaimTimestamp);

    // weth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then acc reward per share = 20 ether / 10 ether (total of borrowed token) = 2 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (10 * 2) - 0 = 20 (precision is 12)
    rewardFacet.claimBorrowingRewardFor(BOB, borrowedToken);

    uint256 _expectedFirstReward = 20 ether;

    _assertAccountReward(BOB, borrowedToken, _expectedFirstReward, _expectedFirstReward.toInt256());
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _expectedFirstReward);

    uint256 _secondClaimTimestamp = _firstClaimTimestamp + 100;
    vm.warp(_secondClaimTimestamp);

    // borrow second time
    vm.startPrank(DEPLOYER);
    chainLinkOracle.add(address(weth), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(usdc), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(isolateToken), address(usd), 1 ether, block.timestamp);
    chainLinkOracle.add(address(btc), address(usd), 10 ether, block.timestamp);
    vm.stopPrank();

    // weth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then new acc reward per share = 20 ether / 10 ether (total of borrowed token) = 2 (precision is 12)
    // total acc reward per share = 2 (old) + 2 = 4 (precision is 12)
    // then update reward per debt to be = 10 * 4 = 40
    int256 _expectedRewardDebtToUpdate = 40 ether;
    vm.prank(BOB);
    borrowFacet.borrow(0, address(weth), 10 ether);
    assertEq(borrowFacet.accountDebtShares(BOB, borrowedToken), 20 ether);
    assertEq(
      rewardFacet.borrowerRewardDebts(BOB, borrowedToken),
      _expectedFirstReward.toInt256() + _expectedRewardDebtToUpdate
    );

    vm.warp(_secondClaimTimestamp + 100);

    // weth pool alloc point is 20
    // given time past 100 sec, reward per sec = 1 ether,  total alloc point is 100
    // then reward = 100 * 1 * 20 / 100 = 20 ether
    // then new acc reward per share = 20 ether / 20 ether (total of borrowed token) = 1 (precision is 12)
    // total acc reward per share = 4 (old) + 1 = 5 (precision is 12)
    // formula of unclaimed reward = (borrowed amount * acc reward per share) - reward debt
    // bob reward debt is 0 now, then unclaimed reward = (20 * 5) - 60 = 40 (precision is 12)
    rewardFacet.claimBorrowingRewardFor(BOB, borrowedToken);

    uint256 _expectedSecondReward = 40 ether;

    uint256 _totalReward = _expectedFirstReward + _expectedSecondReward;
    _assertAccountReward(BOB, borrowedToken, _totalReward, _totalReward.toInt256() + _expectedRewardDebtToUpdate);
    assertEq(rewardToken.balanceOf(address(rewardDistributor)), 1000000 ether - _totalReward);
  }

  function _assertAccountReward(
    address _account,
    address _borrowedToken,
    uint256 _claimedReward,
    int256 _rewardDebt
  ) internal {
    assertEq(rewardToken.balanceOf(_account), _claimedReward);
    assertEq(rewardFacet.borrowerRewardDebts(_account, _borrowedToken), _rewardDebt);
  }
}
