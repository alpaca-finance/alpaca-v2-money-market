// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";

contract LYF_FarmFacetTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserAddFarmPosition_LPShouldBecomeCollateral() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);
    //assert pending reward
    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);

    // asset collat of subaccount
    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountLpTokenCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(wethUsdcLPToken));

    assertEq(_subAccountWethCollat, 0 ether, "eth collat");
    assertEq(_subAccountUsdcCollat, 0 ether, "usdc collat");

    // assume that every coin is 1 dollar and lp = 2 dollar
    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(masterChef)), 30 ether);
    assertEq(_subAccountLpTokenCollat, 30 ether);

    // assert Debt

    (, uint256 _subAccountWethDebtValue) = farmFacet.getDebt(BOB, subAccount0, address(weth), address(wethUsdcLPToken));
    (, uint256 _subAccountUsdcDebtValue) = farmFacet.getDebt(BOB, subAccount0, address(usdc), address(wethUsdcLPToken));

    assertEq(_subAccountWethDebtValue, 10 ether);
    assertEq(_subAccountUsdcDebtValue, 10 ether);

    vm.warp(1);

    uint256 _wethDebtInterest = farmFacet.pendingInterest(address(weth), address(wethUsdcLPToken));
    uint256 _usdcDebtInterest = farmFacet.pendingInterest(address(usdc), address(wethUsdcLPToken));

    // interest model for weth is 0.1 ether per sec
    // interest model for usdc is 0.05 ether per sec
    // given time past is 1 and weth debt and usdc debt are 10 ether
    // then weth pending interest should be 0.1 * 1 * 10 = 1 ether
    // and usdc pending interest should be 0.05 * 1 * 10 = 0.5 ether
    assertEq(_wethDebtInterest, 1 ether);
    assertEq(_usdcDebtInterest, 0.5 ether);

    farmFacet.accureInterest(address(weth), address(wethUsdcLPToken));
    farmFacet.accureInterest(address(usdc), address(wethUsdcLPToken));

    (, uint256 _subAccountWethDebtValueAfter) = farmFacet.getDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    (, uint256 _subAccountUsdcDebtValueAfter) = farmFacet.getDebt(
      BOB,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethDebtValueAfter, 10 ether + _wethDebtInterest);
    assertEq(_subAccountUsdcDebtValueAfter, 10 ether + _usdcDebtInterest);
  }

  function testCorrectness_WhenUserLiquidateLP_TokensShouldBecomeCollateral() external {
    uint256 _wethToAddLP = 10 ether;
    uint256 _usdcToAddLP = 10 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    vm.stopPrank();

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);
    // asset collat of subaccount
    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountLpTokenCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(wethUsdcLPToken));

    assertEq(_subAccountWethCollat, 10 ether);
    assertEq(_subAccountUsdcCollat, 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar

    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(masterChef)), 10 ether);
    assertEq(_subAccountLpTokenCollat, 10 ether);

    // mock remove liquidity will return token0: 2.5 ether and token1: 2.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(2.5 ether, 2.5 ether);

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(mockRouter), 5 ether);
    farmFacet.liquidateLP(subAccount0, address(wethUsdcLPToken), 5 ether);
    vm.stopPrank();

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 0 ether);

    _subAccountWethCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(weth));
    _subAccountUsdcCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(usdc));
    _subAccountLpTokenCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(wethUsdcLPToken));

    assertEq(_subAccountWethCollat, 12.5 ether);
    assertEq(_subAccountUsdcCollat, 12.5 ether);

    assertEq(_subAccountLpTokenCollat, 5 ether);
  }

  function testRevert_WhenUserAddInvalidLYFCollateral_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_InvalidAssetTier.selector));
    farmFacet.liquidateLP(subAccount0, address(weth), 5 ether);
    vm.stopPrank();
  }

  function testCorrectness_GetMMDebt_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    uint256 debtAmount = farmFacet.getMMDebt(address(weth));
    uint256 mmDebtAmount = IMoneyMarket(moneyMarketDiamond).nonCollatGetDebt(address(lyfDiamond), address(weth));

    assertEq(debtAmount, mmDebtAmount);
  }
}
