// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// libraries
import { LibDoublyLinkedList } from "../../contracts/lyf/libraries/LibDoublyLinkedList.sol";
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// interfaces
import { ILYFCollateralFacet } from "../../contracts/lyf/interfaces/ILYFCollateralFacet.sol";

contract LYF_Collateral_TransferCollateralTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testRevert_WhenUserTransferNonCollateralTier_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // borrow weth and usdc
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_OnlyCollateralTierAllowed.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(wethUsdcLPToken), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserTransferCollatMakeSubAccountUnHealthy_ShouldRevert() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _btcCollatAmount = 100 ether;
    btc.mint(BOB, _btcCollatAmount);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(btc), _btcCollatAmount);

    // borrow weth and usdc
    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.expectRevert(abi.encodeWithSelector(ILYFCollateralFacet.LYFCollateralFacet_BorrowingPowerTooLow.selector));
    collateralFacet.transferCollateral(subAccount0, subAccount1, address(btc), _btcCollatAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserTransferCollateralBtwSubAccount_ShouldWork() external {
    address _bobSubAccount0 = LibLYF01.getSubAccount(address(BOB), subAccount0);
    uint256 _transferAmount = 1 ether;
    uint256 _lyfWethCollatBefore;
    uint256 _bobSub0WethCollatBefore;
    uint256 _bobSub0WethCollatAfter;
    LibDoublyLinkedList.Node[] memory _bobSubAccount0collats;
    LibDoublyLinkedList.Node[] memory _bobSubAccount1collats;

    _bobSubAccount0collats = viewFacet.getAllSubAccountCollats(BOB, subAccount0);
    _bobSubAccount1collats = viewFacet.getAllSubAccountCollats(BOB, subAccount1);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 20 ether);

    // before
    _bobSub0WethCollatBefore = viewFacet.getSubAccountTokenCollatAmount(_bobSubAccount0, address(weth));
    _lyfWethCollatBefore = viewFacet.getTokenCollatAmount(address(weth));

    collateralFacet.transferCollateral(subAccount0, subAccount1, address(weth), _transferAmount);
    vm.stopPrank();

    // after
    _bobSub0WethCollatAfter = viewFacet.getSubAccountTokenCollatAmount(_bobSubAccount0, address(weth));

    _bobSubAccount0collats = viewFacet.getAllSubAccountCollats(BOB, subAccount0);
    _bobSubAccount1collats = viewFacet.getAllSubAccountCollats(BOB, subAccount1);

    // fromSubAccount
    assertEq(_bobSub0WethCollatBefore - _bobSub0WethCollatAfter, _transferAmount);

    // toSubAccount
    assertEq(_bobSubAccount1collats.length, 1);
    assertEq(_bobSubAccount1collats[0].amount, _transferAmount);

    // global
    assertEq(_lyfWethCollatBefore - viewFacet.getTokenCollatAmount(address(weth)), 0);
  }
}
