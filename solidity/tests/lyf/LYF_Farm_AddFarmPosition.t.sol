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

contract LYF_Farm_AddFarmPositionTest is LYF_BaseTest {
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
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);
    //assert pending reward
    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);

    // asset collat of subaccount
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(weth));
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(usdc));
    uint256 _subAccountLpTokenCollat = viewFacet.getSubAccountTokenCollatAmount(
      BOB,
      subAccount0,
      address(wethUsdcLPToken)
    );

    assertEq(_subAccountWethCollat, 0, "eth collat");
    assertEq(_subAccountUsdcCollat, 0, "usdc collat");

    // assume that every coin is 1 dollar and lp = 2 dollar
    assertEq(wethUsdcLPToken.balanceOf(lyfDiamond), 0);
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

    assertEq(_subAccountWethDebtValue, 10 ether, "weth debt value");
    assertEq(_subAccountUsdcDebtValue, normalizeEther(10 ether, usdcDecimal), "usdc debt value");

    vm.warp(block.timestamp + 1);

    uint256 _wethUsdcDebtPoolId = viewFacet.getDebtPoolIdOf(address(weth), address(wethUsdcLPToken));
    uint256 _usdcWethDebtPoolId = viewFacet.getDebtPoolIdOf(address(usdc), address(wethUsdcLPToken));

    uint256 _wethDebtInterest = viewFacet.getDebtPoolPendingInterest(_wethUsdcDebtPoolId);
    uint256 _usdcDebtInterest = viewFacet.getDebtPoolPendingInterest(_usdcWethDebtPoolId);

    // interest model for weth is 0.1 ether per sec
    // interest model for usdc is 0.05 ether per sec
    // given time past is 1 and weth debt and usdc debt are 10 ether
    // then weth pending interest should be 0.1 * 1 * 10 = 1 ether
    // and usdc pending interest should be 0.05 * 1 * 10 = 0.5 ether
    assertEq(_wethDebtInterest, 1 ether, "weth debt interest");
    assertEq(_usdcDebtInterest, normalizeEther(0.5 ether, usdcDecimal), "usdc debt interest");

    // Reserve should stay the same
    uint256 _wethReserveBefore = viewFacet.getOutstandingBalanceOf(address(weth));
    uint256 _usdcReserveBefore = viewFacet.getOutstandingBalanceOf(address(usdc));

    uint256 _wethProtocolReserveBefore = viewFacet.getProtocolReserveOf(address(weth));
    uint256 _usdcProtocolReserveBefore = viewFacet.getProtocolReserveOf(address(usdc));

    farmFacet.accrueInterest(address(weth), address(wethUsdcLPToken));
    farmFacet.accrueInterest(address(usdc), address(wethUsdcLPToken));

    // assert that
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), _wethReserveBefore);
    assertEq(viewFacet.getOutstandingBalanceOf(address(usdc)), _usdcReserveBefore);

    assertEq(viewFacet.getProtocolReserveOf(address(weth)), _wethProtocolReserveBefore + _wethDebtInterest);
    assertEq(viewFacet.getProtocolReserveOf(address(usdc)), _usdcProtocolReserveBefore + _usdcDebtInterest);
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

    console.log("s", _usdcDebtInterest);

    assertEq(_subAccountWethDebtValueAfter, 10 ether + _wethDebtInterest, "weth debt value (after)");
    assertEq(
      _subAccountUsdcDebtValueAfter,
      normalizeEther(10 ether, usdcDecimal) + _usdcDebtInterest,
      "usdc debt value (after)"
    );
  }

  function testRevert_WhenAddFarmPosition_BorrowLessThanMinDebtSize_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    adminFacet.setMinDebtSize(20 ether);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // min debt size = 20 usd, borrow only 10 usd of weth
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector));
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    // if one side of the borrowing didn't pass the min debt size should revert
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector));
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), 40 ether, _usdcToAddLP, 0);

    vm.stopPrank();
  }

  function testCorrectness_WhenAddFarmPosition_BorrowMoreThanMinDebtSizeOrNotBorrow_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 30 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

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
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);
    uint256 _wethToIbWeth = 10 ether;
    uint256 _ibWethCollatAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _wethToIbWeth);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    // check collat
    uint256 _subAccountWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(weth));
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(ibWeth));

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
    assertEq(_subAccountUsdcDebtValue, normalizeEther(10 ether, usdcDecimal));
  }

  // ib pair with underlying
  function testCorrectness_WhenUserAddFarmPositionUsingIbInsteadOfUnderlying_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);
    uint256 _ibWethCollatAmount = 30 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    // check collat
    uint256 _subAccountUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(usdc));
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(ibWeth));

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
    assertEq(_subAccountUsdcDebtValue, normalizeEther(10 ether, usdcDecimal));
  }

  // pure 1-sided ib
  function testCorrectness_WhenUserAddFarmPositionWithOnlyIbCollat_ShouldBeAbleToBorrowUsingIbAsCollat() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _ibWethCollatAmount = 60 ether;

    vm.startPrank(EVE);
    IMoneyMarket(moneyMarketDiamond).deposit(address(usdc), normalizeEther(10 ether, usdcDecimal));
    vm.stopPrank();

    vm.startPrank(BOB);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    // check collat
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(ibWeth));

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
    assertEq(_subAccountUsdcDebtValue, normalizeEther(30 ether, usdcDecimal));
  }

  // ib pair with ib
  function testCorrectness_WhenUserAddFarmPositionBothSideIb_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _ibWethCollatAmount = 30 ether;
    uint256 _ibUsdcCollatAmount = normalizeEther(30 ether, ibUsdcDecimal);

    vm.startPrank(BOB);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), _ibWethCollatAmount);
    IMoneyMarket(moneyMarketDiamond).deposit(address(usdc), _ibUsdcCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibWeth), _ibWethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(ibUsdc), _ibUsdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();

    // check collat = 0 because all redeemed
    uint256 _subAccountIbWethCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(ibWeth));
    uint256 _subAccountIbUsdcCollat = viewFacet.getSubAccountTokenCollatAmount(BOB, subAccount0, address(ibUsdc));

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
    uint256 _desiredUsdc = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = normalizeEther(30 ether, usdcDecimal);

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
    assertEq(usdc.balanceOf(BOB), normalizeEther(970 ether, usdcDecimal));

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
    assertEq(_subAccountUsdcDebtValue, 0);
  }

  function testCorrectness_WhenUserDirectAddFarmPositionProvidedAmountGreaterThanDesired_ShouldRevert() external {
    uint256 _desiredWeth = 30 ether;
    uint256 _desiredUsdc = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethAmountDirect = 20 ether;
    uint256 _usdcAmountDirect = normalizeEther(40 ether, usdcDecimal);

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

  function testCorrectness_WhenAddFarmPosition_AndReserveIsMoreThanBorrowedAmount_ShouldBorrowReserve() external {
    // create leftover reserve by borrow from mm and repay so tokens is left in lyf
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(btc), 10 ether);
    farmFacet.addFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      10 ether,
      normalizeEther(10 ether, usdcDecimal),
      10 ether
    );
    mockRouter.setRemoveLiquidityAmountsOut(10 ether, normalizeEther(10 ether, usdcDecimal));
    farmFacet.repay(ALICE, subAccount0, address(weth), address(wethUsdcLPToken), 10 ether);

    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 10 ether);

    // next addFarmPosition should use reserve instead of borrowing from mm
    farmFacet.addFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      6 ether,
      normalizeEther(6 ether, usdcDecimal),
      6 ether
    );
    // 6 ether should be borrowed from reserve so 4 left
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 4 ether);

    // next addFarmPosition should not use reserve but borrow more from mm
    // because amount > reserve
    uint256 _mmDebtBefore = viewFacet.getMMDebt(address(weth));
    farmFacet.addFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      6 ether,
      normalizeEther(6 ether, usdcDecimal),
      6 ether
    );
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 4 ether);
    assertEq(viewFacet.getMMDebt(address(weth)) - _mmDebtBefore, 6 ether);
  }

  function testRevert_WhenUserBorrowMoreThanMaxNumOfDebtPerSubAccount_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    // allow to borrow only 1 token
    adminFacet.setMaxNumOfToken(10, 1);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // borrow both weth and usdc
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_NumberOfTokenExceedLimit.selector));
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();
  }

  function testCorrectness_WhenRepayAndBorrowMoreWithTotalBorrowEqualMaxNumOfDebtPerSubAccount_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _btcToAddLP = 3 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    // allow to borrow 2 tokens
    adminFacet.setMaxNumOfToken(10, 2);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // borrow weth and usdc
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    // repay all debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), type(uint256).max);
    farmFacet.repay(BOB, subAccount0, address(usdc), address(wethUsdcLPToken), type(uint256).max);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount * 2);

    // borrow btc and usdc
    farmFacet.addFarmPosition(subAccount0, address(btcUsdcLPToken), _btcToAddLP, _usdcToAddLP, 0);
    vm.stopPrank();
  }

  function testRevert_WhenAddFarmPositionExceedLPCollatLimit() external {
    // set lp collat limit to 10
    address[] memory _reinvestPath = new address[](2);
    _reinvestPath[0] = address(cake);
    _reinvestPath[1] = address(usdc);

    ILYFAdminFacet.LPConfigInput[] memory lpConfigs = new ILYFAdminFacet.LPConfigInput[](1);
    lpConfigs[0] = ILYFAdminFacet.LPConfigInput({
      lpToken: address(wethUsdcLPToken),
      strategy: address(addStrat),
      masterChef: address(masterChef),
      router: address(mockRouter),
      reinvestPath: _reinvestPath,
      reinvestThreshold: reinvestThreshold,
      rewardToken: address(cake),
      poolId: wethUsdcPoolId,
      maxLpAmount: 10 ether,
      reinvestTreasuryBountyBps: 1500
    });
    adminFacet.setLPConfigs(lpConfigs);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 100 ether);
    // first add 1 lp is fine
    farmFacet.addFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      1 ether
    );
    // 1 + 10 > 10 should revert
    vm.expectRevert(LibLYF01.LibLYF01_LPCollateralExceedLimit.selector);
    farmFacet.addFarmPosition(
      subAccount0,
      address(wethUsdcLPToken),
      10 ether,
      normalizeEther(10 ether, usdcDecimal),
      10 ether
    );
  }
}
