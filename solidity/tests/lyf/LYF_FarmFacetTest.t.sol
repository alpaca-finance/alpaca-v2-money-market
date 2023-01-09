// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// mock
import { MockInterestModel } from "../mocks/MockInterestModel.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

contract LYF_FarmFacetTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    // mint and approve for setting reward in mockMasterChef
    cake.mint(address(this), 100000 ether);
    cake.approve(address(masterChef), type(uint256).max);
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
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountLpTokenCollat = viewFacet.getSubAccountTokenCollatAmount(
      _bobSubaccount,
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethCollat, 0 ether, "eth collat");
    assertEq(_subAccountUsdcCollat, 0 ether, "usdc collat");

    // assume that every coin is 1 dollar and lp = 2 dollar
    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(masterChef)), 30 ether);
    assertEq(_subAccountLpTokenCollat, 30 ether);

    // assert Debt

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

    assertEq(_subAccountWethDebtValue, 10 ether);
    assertEq(_subAccountUsdcDebtValue, 10 ether);

    vm.warp(block.timestamp + 1);

    uint256 _wethDebtInterest = viewFacet.getPendingInterest(address(weth), address(wethUsdcLPToken));
    uint256 _usdcDebtInterest = viewFacet.getPendingInterest(address(usdc), address(wethUsdcLPToken));

    // interest model for weth is 0.1 ether per sec
    // interest model for usdc is 0.05 ether per sec
    // given time past is 1 and weth debt and usdc debt are 10 ether
    // then weth pending interest should be 0.1 * 1 * 10 = 1 ether
    // and usdc pending interest should be 0.05 * 1 * 10 = 0.5 ether
    assertEq(_wethDebtInterest, 1 ether);
    assertEq(_usdcDebtInterest, 0.5 ether);

    farmFacet.accrueInterest(address(weth), address(wethUsdcLPToken));
    farmFacet.accrueInterest(address(usdc), address(wethUsdcLPToken));

    (, uint256 _subAccountWethDebtValueAfter) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    (, uint256 _subAccountUsdcDebtValueAfter) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethDebtValueAfter, 10 ether + _wethDebtInterest);
    assertEq(_subAccountUsdcDebtValueAfter, 10 ether + _usdcDebtInterest);
  }

  function testCorrectness_WhenUserReducePosition_LefoverTokenShouldReturnToUser() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));

    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);
    // asset collat of subaccount
    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountLpTokenCollat = viewFacet.getSubAccountTokenCollatAmount(
      _bobSubaccount,
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethCollat, 0 ether);
    assertEq(_subAccountUsdcCollat, 0 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar

    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(masterChef)), 40 ether);
    assertEq(_subAccountLpTokenCollat, 40 ether);

    // mock remove liquidity will return token0: 2.5 ether and token1: 2.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(2.5 ether, 2.5 ether);

    // should at lest left 18 usd as a debt
    adminFacet.setMinDebtSize(18 ether);

    vm.startPrank(BOB);
    // remove 5 lp,
    // repay 2 eth, 2 usdc
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 5 ether, 0.5 ether, 0.5 ether);
    vm.stopPrank();

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 0 ether);

    _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(usdc));
    _subAccountLpTokenCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(wethUsdcLPToken));

    // assert subaccount's collat
    assertEq(_subAccountWethCollat, 0 ether);
    assertEq(_subAccountUsdcCollat, 0 ether);

    assertEq(_subAccountLpTokenCollat, 35 ether); // starting at 40, remove 5, remain 35

    // assert subaccount's debt
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

    // start at 20, repay 2, remain 18
    assertEq(_subAccountWethDebtValue, 18 ether);
    assertEq(_subAccountUsdcDebtValue, 18 ether);
  }

  function testRevert_WhenUserReducePosition_RemainingDebtIsAboveMinDebtSizeShouldRevert() external {
    // remove interest for convienice of test
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    // asset collat of subaccount
    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountLpTokenCollat = viewFacet.getSubAccountTokenCollatAmount(
      _bobSubaccount,
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethCollat, 0 ether);
    assertEq(_subAccountUsdcCollat, 0 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar

    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0 ether);
    assertEq(wethUsdcLPToken.balanceOf(address(masterChef)), 40 ether);
    assertEq(_subAccountLpTokenCollat, 40 ether);

    // mock remove liquidity will return token0: 15 ether and token1: 15 ether
    mockRouter.setRemoveLiquidityAmountsOut(15 ether, 15 ether);
    adminFacet.setMinDebtSize(10 ether);
    vm.startPrank(BOB);

    // remove 15 lp,
    // repay 15 eth, 15 usdc
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BorrowLessThanMinDebtSize.selector));
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 15 ether, 0 ether, 0 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserReducePosition_IfSlippedShouldRevert() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar
    // mock remove liquidity will return token0: 2.5 ether and token1: 2.5 ether
    mockRouter.setRemoveLiquidityAmountsOut(2.5 ether, 2.5 ether);

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(mockRouter), 5 ether);
    // remove 5 lp,
    // repay 2 eth, 2 usdc
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_TooLittleReceived.selector));
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 5 ether, 3 ether, 3 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserReducePosition_IfResultedInUnhealthyStateShouldRevert() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    // assume that every coin is 1 dollar and lp = 2 dollar
    // mock remove liquidity will return token0: 40 ether and token1: 40 ether
    mockRouter.setRemoveLiquidityAmountsOut(40 ether, 40 ether);

    vm.startPrank(BOB);
    wethUsdcLPToken.approve(address(mockRouter), 40 ether);
    // remove 40 lp,
    // repay 0 eth, 0 usdc
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector));
    farmFacet.reducePosition(subAccount0, address(wethUsdcLPToken), 40 ether, 40 ether, 40 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserAddInvalidLYFCollateral_ShouldRevert() external {
    vm.startPrank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_InvalidAssetTier.selector));
    farmFacet.reducePosition(subAccount0, address(weth), 5 ether, 0, 0);
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

    uint256 debtAmount = viewFacet.getMMDebt(address(weth));
    uint256 mmDebtAmount = IMoneyMarket(moneyMarketDiamond).getNonCollatAccountDebt(address(lyfDiamond), address(weth));

    assertEq(debtAmount, mmDebtAmount);
  }

  function testRevert_WhenAddFarmPosition_BorrowLessThanMinDebtSize_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    adminFacet.setMinDebtSize(20 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // min debt size = 20 usd, borrow only 10 usd of weth
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BorrowLessThanMinDebtSize.selector));
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    // if one side of the borrowing didn't pass the min debt size should revert
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BorrowLessThanMinDebtSize.selector));
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), 40 ether, _usdcToAddLP, 0);

    vm.stopPrank();
  }

  function testCorrectness_WhenAddFarmPosition_BorrowMoreThanMinDebtSizeOrNotBorrow_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 30 ether;
    uint256 _usdcCollatAmount = 20 ether;

    adminFacet.setMinDebtSize(10 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // if there's no borrow, should pass the min
    // borrow weth 10 ether,  borrow usdc 0 ether
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();
  }

  // mix ib + underlying pair with underlying
  function testCorrectness_WhenUserAddFarmPositionWithEnoughUnderlyingAndIbCollatCombined_ShouldUseBothAsCollatAndNotBorrow()
    external
  {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;
    uint256 _wethToIbWeth = 10 ether;
    uint256 _ibWethCollatAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _wethToIbWeth);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));

    // check collat
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(ibWeth));

    assertEq(_subAccountWethCollat, 0);
    assertEq(_subAccountIbWethCollat, 0);

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

    assertEq(_subAccountWethDebtValue, 0);
    assertEq(_subAccountUsdcDebtValue, 10 ether);
  }

  // ib pair with underlying
  function testCorrectness_WhenUserAddFarmPositionUsingIbInsteadOfUnderlying_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _usdcCollatAmount = 20 ether;
    uint256 _ibWethCollatAmount = 30 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));

    // check collat
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(usdc));
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(ibWeth));

    assertEq(_subAccountUsdcCollat, 0);
    assertEq(_subAccountIbWethCollat, 0);

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

    assertEq(_subAccountWethDebtValue, 0);
    assertEq(_subAccountUsdcDebtValue, 10 ether);
  }

  // pure 1-sided ib
  function testCorrectness_WhenUserAddFarmPositionWithOnlyIbCollat_ShouldBeAbleToBorrowUsingIbAsCollat() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _ibWethCollatAmount = 60 ether;

    vm.startPrank(EVE);
    IMoneyMarket(moneyMarketDiamond).deposit(address(usdc), 10 ether);
    vm.stopPrank();

    vm.startPrank(BOB);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));

    // check collat
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(ibWeth));

    assertEq(_subAccountIbWethCollat, 30 ether); // redeem 30 ibWeth for weth

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

    assertEq(_subAccountWethDebtValue, 0); // use ib no need to borrow
    assertEq(_subAccountUsdcDebtValue, 30 ether);
  }

  // ib pair with ib
  function testCorrectness_WhenUserAddFarmPositionBothSideIb_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _ibWethCollatAmount = 30 ether;
    uint256 _ibUsdcCollatAmount = 30 ether;

    vm.startPrank(BOB);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    IMoneyMarket(moneyMarketDiamond).deposit(address(usdc), _ibUsdcCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibUsdc), _ibUsdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));

    // check collat = 0 because all redeemed
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(ibWeth));
    uint256 _subAccountIbUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(ibUsdc));

    assertEq(_subAccountIbWethCollat, 0);
    assertEq(_subAccountIbUsdcCollat, 0);

    // check debt = 0 because we redeem all ib to farm no need to borrow
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

    assertEq(_subAccountWethDebtValue, 0);
    assertEq(_subAccountUsdcDebtValue, 0);
  }

  function testCorrectness_WhenUserDirectAddFarmPositionNormally_ShouldWork() external {
    uint256 _desiredWeth = 30 ether;
    uint256 _desiredUsdc = 30 ether;
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = 30 ether;

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

    assertEq(weth.balanceOf(BOB), 980 ether);
    assertEq(usdc.balanceOf(BOB), 970 ether);

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

    assertEq(_subAccountWethDebtValue, 10 ether);
    assertEq(_subAccountUsdcDebtValue, 0 ether);
  }

  function testCorrectness_WhenUserDirectAddFarmPositionProvidedAmountGreaterThanDesired_ShouldRevert() external {
    uint256 _desiredWeth = 30 ether;
    uint256 _desiredUsdc = 30 ether;
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = 40 ether;

    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_BadInput.selector));
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
  }

  function testCorrectness_WhenUserRepay_SubaccountShouldDecreased() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar
    uint256 _subAccountWethDebtValue;
    vm.startPrank(BOB);
    // 1. repay < debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 5 ether);
    (, _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    // start at 20, repay , remain 15
    assertEq(_subAccountWethDebtValue, 15 ether);

    // 1. repay > debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    (, _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    // start at 20, repay , remain 15
    assertEq(_subAccountWethDebtValue, 0 ether);

    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepayWithCollat_SubaccountShouldDecreased() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar
    uint256 _subAccountWethDebtValue;

    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat;

    // check collat

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 30 ether);
    // 1. repay < debt
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 5 ether);
    (, _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    // start at 20, repay , remain 15, collat left 25
    assertEq(_subAccountWethDebtValue, 15 ether);
    assertEq(_subAccountWethCollat, 25 ether);

    // 1. repay > debt
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    (, _subAccountWethDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    // start at 15, trying to repay 20 (more than debt) , remain 0, collat left 10

    _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(_bobSubaccount, address(weth));
    assertEq(_subAccountWethDebtValue, 0 ether);
    assertEq(_subAccountWethCollat, 10 ether);

    vm.stopPrank();
  }
}
