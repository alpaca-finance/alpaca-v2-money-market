// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet, LibDoublyLinkedList } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

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

    (, uint256 _subAccountWethDebtValue) = farmFacet.getDebt(BOB, subAccount0, address(weth));
    (, uint256 _subAccountUsdcDebtValue) = farmFacet.getDebt(BOB, subAccount0, address(usdc));

    assertEq(_subAccountWethDebtValue, 10 ether);
    assertEq(_subAccountUsdcDebtValue, 10 ether);
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
    vm.stopPrank();

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
