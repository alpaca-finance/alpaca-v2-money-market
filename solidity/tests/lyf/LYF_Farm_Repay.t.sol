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

contract LYF_Farm_RepayTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    // mint and approve for setting reward in mockMasterChef
    cake.mint(address(this), 100000 ether);
    cake.approve(address(masterChef), type(uint256).max);
  }

  function testCorrectness_WhenUserRepay_SubaccountDebtShouldDecrease() external {
    adminFacet.setDebtPoolInterestModel(1, address(new MockInterestModel(0.01 ether)));

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

    masterChef.setReward(wethUsdcPoolId, lyfDiamond, 10 ether);

    assertEq(masterChef.pendingReward(wethUsdcPoolId, lyfDiamond), 10 ether);

    // assume that every coin is 1 dollar and lp = 2 dollar
    uint256 _bobDebtShare;
    uint256 _bobDebtValue;

    (_bobDebtShare, _bobDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );

    assertEq(_bobDebtShare, 20 ether, "expected debt share before repay is not match");
    assertEq(_bobDebtValue, 20 ether, "expected debt value before repay is not match");

    // warp time to make share value changed
    // before debt share = 20, debt value = 20
    vm.warp(block.timestamp + 10);
    uint256 _wethUsdcLPDebtPoolId = viewFacet.getDebtPoolIdOf(address(weth), address(wethUsdcLPToken));
    uint256 _wethPendingInterest = viewFacet.getDebtPoolPendingInterest(_wethUsdcLPDebtPoolId);
    uint256 _wethProtocolReserveBefore = viewFacet.getProtocolReserveOf(address(weth));
    uint256 _wethOutstandingBefore = viewFacet.getOutstandingBalanceOf(address(weth));

    // timepast * interest rate * debt value = 10 * 0.01 * 20 = 2
    assertEq(_wethPendingInterest, 2 ether, "expected interest is not match");

    vm.startPrank(BOB);
    // 1. repay < debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 5 ether);
    (_bobDebtShare, _bobDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );

    // after accure debt share = 20, debt value = 22
    // user repay 5 shares
    // actual repay amount = 5 * 22 / 20 = 5.5 tokens
    assertEq(_bobDebtShare, 15 ether, "expected debt shares mismatch"); // 20 - 5 = 15
    assertEq(_bobDebtValue, 16.5 ether, "expected debt value mismatch"); // 22 - 5.5 = 16.5

    // assert protocol revenue and outstanding balance
    assertEq(viewFacet.getProtocolReserveOf(address(weth)), _wethProtocolReserveBefore + _wethPendingInterest);
    // outstanding after should increase by repay amount - interest collected
    // repaying 5.5 ether, 2 of which is an interest, 3.5 left as an outstanding
    uint256 _expectedOutstandingAfterRepay = _wethOutstandingBefore + 3.5 ether;
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), _expectedOutstandingAfterRepay);
    vm.stopPrank();

    // test withdraw reserve
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.withdrawReserve(address(weth), address(this), 2 ether);

    adminFacet.withdrawReserve(address(weth), address(this), 2 ether);
    assertEq(viewFacet.getProtocolReserveOf(address(weth)), 0);
    // should not change the outstanding since it decrease protocol reserve and increase reverse at the same time
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), _expectedOutstandingAfterRepay);

    vm.startPrank(BOB);
    // 2. repay > debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    (_bobDebtShare, _bobDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );

    // after accure debt share = 15, debt value = 16.5
    // user repay 20 shares but can pay only 15 (debt share)
    // actual repay amount = 15 * 16.5 / 15 = 16.5 tokens
    assertEq(_bobDebtShare, 0 ether, "still has debt share remaining"); // 15 - 15 = 0
    assertEq(_bobDebtValue, 0 ether, "still has debt value remaining"); // 16.5 - 16.5 = 0

    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepay_RemainingDebtBelowMinDebtSize_ShouldRevert() external {
    adminFacet.setMinDebtSize(20 ether);

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

    // assume that every coin is 1 dollar and lp = 2 dollar
    vm.startPrank(BOB);
    // should revert as min debt size = 20, repaying 10 would left 10 in the subaccount
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector));
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 10 ether);

    // should be ok if repay whole debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    farmFacet.repay(BOB, subAccount0, address(usdc), address(wethUsdcLPToken), 20 ether);

    vm.stopPrank();
  }
}
