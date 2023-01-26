// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_Farm_ReinvestTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();

    // inject token to router for swap
    usdc.mint(address(mockRouter), 1000 ether);
    weth.mint(address(mockRouter), 1000 ether);
  }

  function testCorrectness_WhenReinvestisCalled_ShouldConvertRewardTokenToLP() external {
    uint256 _desiredWeth = 30 ether;
    uint256 _desiredUsdc = 30 ether;
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = 30 ether;

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    vm.startPrank(BOB);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _desiredWeth,
      _desiredUsdc,
      0,
      _wethAmountDirect,
      _usdcAmountDirect
    );
    vm.stopPrank();

    (uint256 _lpBalance, ) = masterChef.userInfo(_lpConfig.poolId, lyfDiamond);

    // farm at master chef
    // adding liquidity first time of weth-usdc
    // weth = 30 and usdc = 30, so lp = 30
    assertEq(_lpBalance, 30 ether);
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), 30 ether);

    // time pass and reward pending in MasterChef = 3
    cake.mint(address(this), 3 ether);
    cake.approve(address(masterChef), 3 ether);
    masterChef.setReward(_lpConfig.poolId, lyfDiamond, 3 ether);

    // set reinvestor and call reinvest
    address[] memory addresses = new address[](1);
    addresses[0] = address(this);
    adminFacet.setReinvestorsOk(addresses, true);
    farmFacet.reinvest(address(wethUsdcLPToken));

    (_lpBalance, ) = masterChef.userInfo(_lpConfig.poolId, lyfDiamond);

    // lp should increase
    // total Reward = 3 reward bouty = 3 * 15 / 100 = 0.45 ether
    // actual 3 - 0.45 = 2.55 swap to token0 = 1.275 and token1 = 1.275
    // lpReceive = 1.275, 30 + 1.275 = 31.275
    assertEq(_lpBalance, 31.275 ether);
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), 31.275 ether);
    assertEq(viewFacet.getPendingReward(address(wethUsdcLPToken)), 0);

    // treasury should received bounty
    assertEq(MockERC20(_lpConfig.rewardToken).balanceOf(treasury), 0.45 ether);
  }

  function testCorrectness_WhenPendingRewardLessThanReinvestThreshold_ShouldSkipReinvest() external {
    uint256 _desiredWeth = 30 ether;
    uint256 _desiredUsdc = 30 ether;
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = 30 ether;

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    vm.startPrank(BOB);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _desiredWeth,
      _desiredUsdc,
      0,
      _wethAmountDirect,
      _usdcAmountDirect
    );
    vm.stopPrank();

    (uint256 _lpBalance, ) = masterChef.userInfo(_lpConfig.poolId, lyfDiamond);

    // farm at master chef
    // adding liquidity first time of weth-usdc
    // weth = 30 and usdc = 30, so lp = 30
    assertEq(_lpBalance, 30 ether);
    // no pending reward
    assertEq(viewFacet.getPendingReward(address(wethUsdcLPToken)), 0);

    // time pass and some reward pending in MasterChef
    uint256 _rewardAmount = reinvestThreshold - 1;
    cake.mint(address(this), _rewardAmount);
    cake.approve(address(masterChef), _rewardAmount);
    masterChef.setReward(_lpConfig.poolId, lyfDiamond, _rewardAmount);

    //BOB add more LP to subaccount
    vm.startPrank(BOB);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _desiredWeth,
      _desiredUsdc,
      0,
      _wethAmountDirect,
      _usdcAmountDirect
    );
    vm.stopPrank();

    // no reinvest, pending reward not reset
    assertGt(viewFacet.getPendingReward(address(wethUsdcLPToken)), 0);
  }

  function testCorrectness_WhenLPCollatAdded_PendingRewardMoreThanReinvestThreshold_ShouldReinvestToMakeLPFair()
    external
  {
    uint256 _bobLpAmount = 50 ether;
    uint256 _aliceLpAmount = 30 ether;

    wethUsdcLPToken.mint(address(BOB), _bobLpAmount);
    wethUsdcLPToken.mint(address(ALICE), _aliceLpAmount);

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(lyfDiamond), type(uint256).max);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount
    );
    vm.stopPrank();

    // BOB frist deposit lp, lpShare = lpValue = depositAmount = 50
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), _bobLpAmount);
    assertEq(viewFacet.getLpTokenShare(address(wethUsdcLPToken)), _bobLpAmount);

    // time pass and reward pending in MasterChef = 20
    cake.mint(address(this), 20 ether);
    cake.approve(address(masterChef), 20 ether);
    masterChef.setReward(_lpConfig.poolId, lyfDiamond, 20 ether);

    // ALICE deposit another 30 lp
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(address(lyfDiamond), type(uint256).max);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount
    );
    vm.stopPrank();

    // To make LP fair pending reward is reinvestd before calcualting alice's share
    // 20 reward token can compose to LP = 10
    // bouty should be 15% of reward = 20 * 15 / 100 = 3 ether
    // actual reward 17 ether - convert to LP 17 / 2 = 8.5 ether
    // total lpValues with reward = 50 + 8.5 = 58.5

    // bob shares = 50
    // alice should get 30 * 50 / 58.5 = 25.641025641025641025 shares
    // totalShare = 50 + 25.641025641025641025 = 75.641025641025641025

    // alice deposit another 30 lp
    // total lpValues = 58.5 + 30  = 88.5
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), 88.5 ether);
    assertEq(viewFacet.getLpTokenShare(address(wethUsdcLPToken)), 75.641025641025641025 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(wethUsdcLPToken)), 50 ether);
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, address(wethUsdcLPToken)),
      25.641025641025641025 ether
    );

    // treasury should received bounty
    assertEq(MockERC20(_lpConfig.rewardToken).balanceOf(treasury), 3 ether);
  }

  function testCorrectness_WhenLPCollatRemoved_PendingRewardMoreThanReinvestThreshold_ShouldReinvestToMakeLPFair()
    external
  {
    uint256 _bobLpAmount = 50 ether;
    uint256 _aliceLpAmount = 25 ether;

    wethUsdcLPToken.mint(address(BOB), _bobLpAmount);
    wethUsdcLPToken.mint(address(ALICE), _aliceLpAmount);

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(lyfDiamond), type(uint256).max);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount,
      _bobLpAmount
    );
    vm.stopPrank();

    // BOB frist deposit lp, lpShare = lpValue = depositAmount = 50
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), _bobLpAmount);
    assertEq(viewFacet.getLpTokenShare(address(wethUsdcLPToken)), _bobLpAmount);

    // ALICE deposit another 25 lp
    vm.startPrank(ALICE);
    wethUsdcLPToken.approve(address(lyfDiamond), type(uint256).max);
    farmFacet.directAddFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount,
      _aliceLpAmount
    );
    vm.stopPrank();

    // bob shares = 50
    // alice get = 25 * 50 / 50 = 25 shares
    // totalLPValues = 75
    // totalShares = 75
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), 75 ether);
    assertEq(viewFacet.getLpTokenShare(address(wethUsdcLPToken)), 75 ether);

    // time pass and reward pending in MasterChef = 20
    cake.mint(address(this), 20 ether);
    cake.approve(address(masterChef), 20 ether);
    masterChef.setReward(_lpConfig.poolId, lyfDiamond, 20 ether);

    // now lp is get reinvest and lpValue increase before shares is removed
    // bob remove 10 shares
    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(lyfDiamond), type(uint256).max);
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 10 ether, 0, 0);
    vm.stopPrank();

    // reward 20, bounty (15%) 3 ether
    // reward to add liquidity when reinvest = 17 then liquidity receive is 8.5 (17 / 2 (mockRouter))
    // lp value = 75 + 8.5 = 83.5
    // 10 shares = 10 * 83.5  / 75 = 11.133333333333333333 lpValue
    // totalLPValues = 75 + 8.5 - 11.133333333333333333 = 72.366666666666666667
    // totalShares = 65
    assertEq(viewFacet.getLpTokenAmount(address(wethUsdcLPToken)), 72.366666666666666667 ether);
    assertEq(viewFacet.getLpTokenShare(address(wethUsdcLPToken)), 65 ether);

    // treasury should received bounty
    assertEq(MockERC20(_lpConfig.rewardToken).balanceOf(treasury), 3 ether);
  }

  function testRevert_WhenNotReinvestorCallReinvest_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_Unauthorized.selector));
    farmFacet.reinvest(address(wethUsdcLPToken));
  }
}