// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";

// interfaces
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";

contract LYF_Collateral_TransferCollateralTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenUserTransferNonCollateralTier_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = normalizeEther(20 ether, usdcDecimal);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // borrow weth and usdc
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

    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_OnlyCollateralTierAllowed.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(wethUsdcLPToken), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserTransferUnlistedTier_ShouldRevert() external {
    address _unlisted = address(0);
    vm.startPrank(BOB);
    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_OnlyCollateralTierAllowed.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount1, _unlisted, 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserTransferCollatMakeSubAccountUnHealthy_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = normalizeEther(30 ether, usdcDecimal);
    uint256 _btcCollatAmount = 100 ether;
    btc.mint(BOB, _btcCollatAmount);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(btc), _btcCollatAmount);

    // borrow weth and usdc
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

    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_BorrowingPowerTooLow.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(btc), _btcCollatAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserTransferCollateralBtwSubAccount_ShouldWork() external {
    uint256 _transferAmount = 1 ether;
    uint256 _lyfWethCollatBefore;
    uint256 _bobSub0WethCollatBefore;
    uint256 _bobSub0WethCollatAfter;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 20 ether);

    // before
    _bobSub0WethCollatBefore = viewFacet.getSubAccountTokenCollatAmount(address(BOB), subAccount0, address(weth));
    _lyfWethCollatBefore = viewFacet.getTokenCollatAmount(address(weth));

    collateralFacet.transferCollateral(subAccount0, subAccount1, address(weth), _transferAmount);
    vm.stopPrank();

    // after
    _bobSub0WethCollatAfter = viewFacet.getSubAccountTokenCollatAmount(address(BOB), subAccount0, address(weth));

    LibDoublyLinkedList.Node[] memory _bobSubAccount1collats = viewFacet.getAllSubAccountCollats(BOB, subAccount1);

    // fromSubAccount
    assertEq(_bobSub0WethCollatBefore - _bobSub0WethCollatAfter, _transferAmount);

    // toSubAccount
    assertEq(_bobSubAccount1collats.length, 1);
    assertEq(_bobSubAccount1collats[0].amount, _transferAmount);

    // global
    assertEq(_lyfWethCollatBefore - viewFacet.getTokenCollatAmount(address(weth)), 0);
  }

  function testRevert_TransferCollatBtwSameSubAccount() external {
    vm.prank(BOB);
    vm.expectRevert(ILYFCollateralFacet.LYFCollateralFacet_SelfCollatTransferNotAllowed.selector);
    collateralFacet.transferCollateral(subAccount0, subAccount0, address(weth), 1 ether);
  }
}
