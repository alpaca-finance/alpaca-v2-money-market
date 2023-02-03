// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { LYF_BaseTest, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { ILYFViewFacet } from "../../contracts/lyf/interfaces/ILYFViewFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";

contract LYF_Admin_SettleDebtTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminFulllySettleDebt_MMDebtShouldBeZero() external {
    address _borrowToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    // borrow MM for 30 usdc
    // [after open position] usdc debt -> value: 30, share: 30
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 0,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    // [after repaid (10 ether)] usdc debt -> value: 20, share: 20
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, address(usdc), address(wethUsdcLPToken), normalizeEther(10 ether, usdcDecimal));

    // warp time to make share value changed
    vm.warp(block.timestamp + 10);

    // [after repaid (20 ether)] usdc debt -> value: 15, share: 10
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, address(usdc), address(wethUsdcLPToken), normalizeEther(20 ether, usdcDecimal));

    assertEq(viewFacet.getMMDebt(_borrowToken), normalizeEther(30 ether, usdcDecimal));
    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), normalizeEther(30 ether, usdcDecimal));

    // settle debt
    // reserve will be equal to outstanding balance
    // protocolReserve should not be affected, so protocolReserve = 10 usdc
    // Note: try to settle 1000 usdc, but only 30 usdc is settled (cap at MM debt)
    adminFacet.settleDebt(_borrowToken, normalizeEther(1000 ether, usdcDecimal));
    assertEq(viewFacet.getMMDebt(_borrowToken), 0);
    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), 0);
    assertEq(viewFacet.getProtocolReserveOf(_borrowToken), normalizeEther(10 ether, usdcDecimal));
  }

  function testCorrectness_WhenAdminPartiallySettleDebt_MMDebtShouldBeRemained() external {
    address _borrowToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    // borrow MM for 30 usdc
    // [after open position] usdc debt -> value: 30, share: 30
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 0,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    // [after repaid (10 ether)] usdc debt -> value: 20, share: 20
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, address(usdc), address(wethUsdcLPToken), normalizeEther(10 ether, usdcDecimal));

    // settle debt
    // reserve will be equal to outstanding balance
    adminFacet.settleDebt(_borrowToken, normalizeEther(10 ether, usdcDecimal));
    assertEq(viewFacet.getMMDebt(_borrowToken), normalizeEther(20 ether, usdcDecimal));
    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), 0);
    assertEq(viewFacet.getProtocolReserveOf(_borrowToken), 0);
  }

  function testRevert_WhenAdminSettleDebtWithNotEnoughBalance() external {
    address _borrowToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = normalizeEther(10 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 0,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    // alice repay 10 usdc => outstanding balance = 10 usdc
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, _borrowToken, address(wethUsdcLPToken), _repayAmount);

    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), _repayAmount);
    assertEq(viewFacet.getMMDebt(_borrowToken), normalizeEther(30 ether, usdcDecimal));

    // settle debt (should revert since not enough balance)
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_NotEnoughToken.selector);
    adminFacet.settleDebt(_borrowToken, normalizeEther(30 ether, usdcDecimal));
  }

  function testRevert_WhenAdminSettleDebtWithNoDebt() external {
    // assume no debt
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_NoMoneyMarketDebt.selector);
    adminFacet.settleDebt(address(weth), 0);
  }

  function testRevert_WhenNonAdminSettleDebt() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.settleDebt(address(weth), 0);
  }
}
