// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { LYF_BaseTest, ILYFAdminFacet } from "./LYF_BaseTest.t.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { ILYFViewFacet } from "../../contracts/lyf/interfaces/ILYFViewFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";

contract LYF_Admin_SettleDebtTest is LYF_BaseTest {
  address _borrowToken;
  address _lpToken;

  function setUp() public override {
    super.setUp();

    _borrowToken = address(usdc);
    _lpToken = address(wethUsdcLPToken);
  }

  function _setupMMDebt() internal {
    // borrow MM for 30 usdc
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

    // check that lyf non collat borrow mm for 30 usdc
    assertEq(viewFacet.getMMDebt(_borrowToken), normalizeEther(30 ether, usdcDecimal));
  }

  function testCorrectness_WhenAdminFulllySettleDebt_MMDebtShouldBeZero() external {
    // [after open position] usdc debt -> value: 30, share: 30
    _setupMMDebt();

    // [after repaid (10 ether)] usdc debt -> value: 20, share: 20
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, address(usdc), address(wethUsdcLPToken), normalizeEther(10 ether, usdcDecimal));

    // warp time to make share value changed
    vm.warp(block.timestamp + 10);

    uint256 _pendingInterest = viewFacet.getDebtPoolPendingInterest(viewFacet.getDebtPoolIdOf(_borrowToken, _lpToken));

    // [after repaid (20 ether)] usdc debt -> value: 0, share: 0
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, address(usdc), address(wethUsdcLPToken), normalizeEther(20 ether, usdcDecimal));
    viewFacet.getSubAccountDebt(ALICE, subAccount0, _borrowToken, _lpToken);

    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), normalizeEther(30 ether, usdcDecimal));

    uint256 _protocolReserve = viewFacet.getProtocolReserveOf(_borrowToken);

    viewFacet.getMMDebt(_borrowToken);

    // settle debt
    // reserve will be equal to outstanding balance
    // protocolReserve should not be affected, so protocolReserve = 10 usdc
    adminFacet.settleDebt(_borrowToken, normalizeEther(30 ether, usdcDecimal));
    assertEq(viewFacet.getMMDebt(_borrowToken), 0);
    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), 0);
    assertEq(_protocolReserve, normalizeEther(10 ether, usdcDecimal));
  }

  function testCorrectness_WhenAdminPartiallySettleDebt_MMDebtShouldBeRemained() external {
    // [after open position] usdc debt -> value: 30, share: 30
    _setupMMDebt();

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
    uint256 _repayAmount = normalizeEther(10 ether, usdcDecimal);

    // [after open position] usdc debt -> value: 30, share: 30
    _setupMMDebt();

    // alice repay 10 usdc => outstanding balance = 10 usdc
    vm.prank(ALICE);
    farmFacet.repay(ALICE, subAccount0, _borrowToken, address(wethUsdcLPToken), _repayAmount);

    assertEq(viewFacet.getOutstandingBalanceOf(_borrowToken), _repayAmount);
    assertEq(viewFacet.getMMDebt(_borrowToken), normalizeEther(30 ether, usdcDecimal));

    // settle debt (should revert since not enough balance)
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_NotEnoughToken.selector);
    adminFacet.settleDebt(_borrowToken, normalizeEther(30 ether, usdcDecimal));
  }

  function testRevert_WhenAdminSettleDebtWithZeroAmount() external {
    // assume no debt
    vm.expectRevert(ILYFAdminFacet.LYFAdminFacet_InvalidArguments.selector);
    adminFacet.settleDebt(address(weth), 0);
  }

  function testRevert_WhenNonAdminSettleDebt() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.settleDebt(address(weth), 1);
  }
}
