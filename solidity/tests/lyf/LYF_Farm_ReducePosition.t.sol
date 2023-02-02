// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// mock
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../../contracts/lyf/libraries/LibUIntDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// TODO: refactor this test
contract LYF_Farm_ReducePositionTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    // mint and approve for setting reward in mockMasterChef
    cake.mint(address(this), 100000 ether);
    cake.approve(address(masterChef), type(uint256).max);
  }

  function testCorrectness_WhenUserReducePosition_LeftoverTokenShouldReturnToUser() external {
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = normalizeEther(40 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: _usdcToAddLP,
      token0ToBorrow: _wethToAddLP,
      token1ToBorrow: _usdcToAddLP,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(wethUsdcLPToken)), 40 ether);

    // mock remove liquidity will return token0: 2.5 ether and token1: 2.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(2.5 ether, normalizeEther(2.5 ether, usdcDecimal));

    // should at lest left 38 usd as a debt
    adminFacet.setMinDebtSize(38 ether);

    // remove 5 lp,
    // repay 2 eth, 2 usdc
    vm.prank(BOB);
    farmFacet.reducePosition(
      subAccount0,
      address(wethUsdcLPToken),
      5 ether,
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal)
    );

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 0 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(wethUsdcLPToken)), 35 ether); // starting at 40, remove 5, remain 35

    // check debt
    (, uint256 _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    (, uint256 _subAccountUsdcDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );
    // start at 40, repay 2, remain 38
    assertEq(_subAccountWethDebtValue, 38 ether);
    assertEq(_subAccountUsdcDebtValue, normalizeEther(38 ether, usdcDecimal));
  }

  function testCorrectness02_WhenUserReducePosition_LefoverTokenShouldReturnToUser() external {
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = normalizeEther(40 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: _usdcToAddLP,
      token0ToBorrow: _wethToAddLP,
      token1ToBorrow: _usdcToAddLP,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(wethUsdcLPToken)), 40 ether);

    // mock remove liquidity will return token0: 30 ether and token1: 30 ether
    mockRouter.setRemoveLiquidityAmountsOut(30 ether, normalizeEther(30 ether, usdcDecimal));

    // should at lest left 10 usd as a debt
    adminFacet.setMinDebtSize(10 ether);

    uint256 wethBefore = weth.balanceOf(BOB);
    uint256 usdcBefore = usdc.balanceOf(BOB);

    // remove 5 lp,
    // repay 25 eth, 25 usdc
    vm.prank(BOB);
    farmFacet.reducePosition(
      subAccount0,
      address(wethUsdcLPToken),
      5 ether,
      5 ether,
      normalizeEther(5 ether, usdcDecimal)
    );

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 0 ether);
    // starting at 40, remove 5, remain 35
    assertEq(viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(wethUsdcLPToken)), 35 ether);

    // check debt
    (, uint256 _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    (, uint256 _subAccountUsdcDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );

    // debt start at 40, get 30, repay 25, remain 15, transfer back 5
    assertEq(_subAccountWethDebtValue, 15 ether);
    assertEq(_subAccountUsdcDebtValue, normalizeEther(15 ether, usdcDecimal));

    assertEq(weth.balanceOf(BOB) - wethBefore, 5 ether, "BOB get WETH back wrong");
    assertEq(usdc.balanceOf(BOB) - usdcBefore, normalizeEther(5 ether, usdcDecimal), "BOB get USDC back wrong");
  }

  function testRevert_WhenUserReducePosition_RemainingDebtIsLessThanMinDebtSizeShouldRevert() external {
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = normalizeEther(40 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: _usdcToAddLP,
      token0ToBorrow: _wethToAddLP - _wethCollatAmount,
      token1ToBorrow: _usdcToAddLP - _usdcCollatAmount,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    // mock remove liquidity will return token0: 15 ether and token1: 15 ether
    mockRouter.setRemoveLiquidityAmountsOut(15 ether, normalizeEther(15 ether, usdcDecimal));

    adminFacet.setMinDebtSize(10 ether);

    // remove 15 lp,
    // repay 15 eth, 15 usdc
    vm.prank(BOB);
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector));
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 15 ether, 0, 0);
  }

  function testRevert_WhenUserReducePosition_IfSlippedShouldRevert() external {
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = normalizeEther(40 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: _usdcToAddLP,
      token0ToBorrow: _wethToAddLP,
      token1ToBorrow: _usdcToAddLP,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);

    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar
    // mock remove liquidity will return token0: 2.5 ether and token1: 2.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(2.5 ether, normalizeEther(2.5 ether, usdcDecimal));

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(mockRouter), 5 ether);
    // remove 5 lp,
    // repay 2 eth, 2 usdc
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_TooLittleReceived.selector));
    farmFacet.reducePosition(
      subAccount0,
      address(wethUsdcLPToken),
      5 ether,
      3 ether,
      normalizeEther(3 ether, usdcDecimal)
    );
    vm.stopPrank();
  }

  function testRevert_WhenUserReducePosition_IfResultedInUnhealthyStateShouldRevert() external {
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = normalizeEther(40 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: _usdcToAddLP,
      token0ToBorrow: _wethToAddLP,
      token1ToBorrow: _usdcToAddLP,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);

    vm.stopPrank();

    // assume that every coin is 1 dollar and lp = 2 dollar
    // mock remove liquidity will return token0: 40 ether and token1: 40 ether
    mockRouter.setRemoveLiquidityAmountsOut(40 ether, normalizeEther(40 ether, usdcDecimal));

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(mockRouter), 40 ether);
    // remove 40 lp,
    // repay 0 eth, 0 usdc
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector));
    farmFacet.reducePosition(
      subAccount0,
      address(wethUsdcLPToken),
      40 ether,
      40 ether,
      normalizeEther(40 ether, usdcDecimal)
    );
    vm.stopPrank();
  }

  function testRevert_WhenUserAddInvalidLYFCollateral_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_InvalidAssetTier.selector));
    farmFacet.reducePosition(subAccount0, address(weth), 5 ether, 0, 0);
    vm.stopPrank();
  }
}
