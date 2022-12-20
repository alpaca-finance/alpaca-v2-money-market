// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_AdminFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetTokenToIbTokens_ShouldWork() external {
    address _depositToken = address(9998);
    address _ibDepositToken = address(9999);

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](1);
    _ibPair[0] = IAdminFacet.IbPair({ token: _depositToken, ibToken: _ibDepositToken });

    adminFacet.setTokenToIbTokens(_ibPair);

    assertEq(adminFacet.tokenToIbTokens(_depositToken), _ibDepositToken);
    assertEq(adminFacet.ibTokenToTokens(_ibDepositToken), _depositToken);
  }

  function testCorrectness_WhenAdminSetTokenConfig_ShouldWork() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    adminFacet.setTokenConfigs(_inputs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = adminFacet.tokenConfigs(address(weth));

    // assertEq not accept enum
    assertTrue(_tokenConfig.tier == LibMoneyMarket01.AssetTier.COLLATERAL);
    assertEq(_tokenConfig.collateralFactor, 5000);
    assertEq(_tokenConfig.borrowingFactor, 6000);
  }

  function testCorrectness_WhenNonAdminSetSomeConfig_ShouldRevert() external {
    vm.startPrank(ALICE);

    // try to setTokenToIbTokens
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](1);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(9998), ibToken: address(9999) });
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTokenToIbTokens(_ibPair);

    // try to setTokenConfigs
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTokenConfigs(_inputs);

    vm.stopPrank();
  }

  function testRevert_WhenAdminTryAddDuplicatedLendingPool_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_PoolIsAlreadyAdded.selector));
    adminFacet.addLendingPool(address(rewardToken), address(ibWeth), 20);
  }

  function testCorrectness_WhenAdminSetLendingPool_AllocPointShouldBeCorrected() external {
    assertEq(rewardFacet.getLendingPool(address(rewardToken), address(ibWeth)).allocPoint, 20);
    adminFacet.setLendingPool(address(rewardToken), address(ibWeth), 40);
    assertEq(rewardFacet.getLendingPool(address(rewardToken), address(ibWeth)).allocPoint, 40);
  }

  function testRevert_WhenAdminTryAddDuplicatedBorrowingPool_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_PoolIsAlreadyAdded.selector));
    adminFacet.addBorrowingPool(address(rewardToken), address(weth), 20);
  }

  function testCorrectness_WhenAdminSetBorrowingPool_AllocPointShouldBeCorrected() external {
    assertEq(rewardFacet.getBorrowingPool(address(rewardToken), address(weth)).allocPoint, 20);
    adminFacet.setBorrowingPool(address(rewardToken), address(weth), 40);
    assertEq(rewardFacet.getBorrowingPool(address(rewardToken), address(weth)).allocPoint, 40);
  }

  function testRevert_WhenAdminTryAddOrSetInvalidToken_ShouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.addLendingPool(address(rewardToken), address(0), 20);
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.setLendingPool(address(rewardToken), address(0), 20);
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.addBorrowingPool(address(rewardToken), address(0), 20);
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidAddress.selector));
    adminFacet.setBorrowingPool(address(rewardToken), address(0), 20);
  }

  function testCorrectness_WhenAdminManageLendingRewardPerSec_ShouldWork() external {
    adminFacet.addLendingRewardPerSec(address(rewardToken2), 2 ether);
    assertEq(adminFacet.getLendingRewardPerSec(address(rewardToken2)), 2 ether);
    // reward 1 should be not affected
    assertEq(adminFacet.getLendingRewardPerSec(address(rewardToken)), 1 ether);

    adminFacet.updateLendingRewardPerSec(address(rewardToken), 3 ether);
    assertEq(adminFacet.getLendingRewardPerSec(address(rewardToken)), 3 ether);
    // reward 2 should be not affected
    assertEq(adminFacet.getLendingRewardPerSec(address(rewardToken2)), 2 ether);
  }

  function testCorrectness_WhenAdminManageBorrowingRewardPerSec_ShouldWork() external {
    adminFacet.addBorrowingRewardPerSec(address(rewardToken2), 2 ether);
    assertEq(adminFacet.getBorrowingRewardPerSec(address(rewardToken2)), 2 ether);
    // reward 1 should be not affected
    assertEq(adminFacet.getBorrowingRewardPerSec(address(rewardToken)), 1 ether);

    adminFacet.updateBorrowingRewardPerSec(address(rewardToken), 3 ether);
    assertEq(adminFacet.getBorrowingRewardPerSec(address(rewardToken)), 3 ether);
    // reward 2 should be not affected
    assertEq(adminFacet.getBorrowingRewardPerSec(address(rewardToken2)), 2 ether);
  }
}
