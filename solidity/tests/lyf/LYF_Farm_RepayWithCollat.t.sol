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

contract LYF_Farm_RepayWithCollatTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    // mint and approve for setting reward in mockMasterChef
    cake.mint(address(this), 100000 ether);
    cake.approve(address(masterChef), type(uint256).max);
  }

  function testCorrectness_WhenUserRepayWithCollat_SubaccountShouldDecreased() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0.01 ether)));
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
    vm.warp(block.timestamp + 25);

    // timepast * interest rate * debt value = 25 * 0.01 * 20 = 5
    assertEq(
      viewFacet.getPendingInterest(address(weth), address(wethUsdcLPToken)),
      5 ether,
      "expected interest is not match"
    );

    vm.startPrank(BOB);
    // add more collat for repay
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 30 ether);

    // 1. repay < debt
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 5 ether);
    (_bobDebtShare, _bobDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );

    // after accure debt share = 20, debt value = 25
    // user repay 5 share
    // actual repay share = 5 * 25 / 20 = 6.25 ether
    assertEq(_bobDebtShare, 15 ether, "expected debt shares is mismatch"); // 20 - 5 = 15
    assertEq(_bobDebtValue, 18.75 ether, "expected debt value is mismatch"); // 25 - 6.25 = 18.75

    // 2. repay > debt
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    (_bobDebtShare, _bobDebtValue) = viewFacet.getSubAccountDebt(
      BOB,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );

    // after accure debt share = 15, debt value = 18.75
    // user repay 20 share but can pay only 15
    // actual repay amount = 15 * 18.75 / 15 = 18.75 tokens
    assertEq(_bobDebtShare, 0 ether, "still has debt share remaining");
    assertEq(_bobDebtValue, 0 ether, "still has debt value remaining");

    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepayWithCollat_RemainingDebtBelowMinDebtSize_ShouldRevert() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0)));
    adminFacet.setDebtInterestModel(2, address(new MockInterestModel(0)));

    adminFacet.setMinDebtSize(20 ether);
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
    vm.startPrank(BOB);
    // Add collater first to be able to repay with collat
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    // should revert as min debt size = 20, repaying 10 would left 10 in the subaccount
    vm.expectRevert(abi.encodeWithSelector(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector));
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 10 ether);

    // should be ok if repay whole debt
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
    farmFacet.repayWithCollat(subAccount0, address(usdc), address(wethUsdcLPToken), 20 ether);

    vm.stopPrank();
  }

  function testRevert_WhenUserRepayMoreThanCollat() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0.01 ether)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    vm.prank(BOB);
    // repay without collat amount
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector));
    farmFacet.repayWithCollat(subAccount0, address(weth), address(wethUsdcLPToken), 20 ether);
  }

  function testRevert_WhenUserRepayNonCollateralAsset() external {
    // remove interest for convienice of test
    adminFacet.setDebtInterestModel(1, address(new MockInterestModel(0.01 ether)));
    uint256 _wethToAddLP = 40 ether;
    uint256 _usdcToAddLP = 40 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _usdcCollatAmount);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), _wethToAddLP, _usdcToAddLP, 0);

    vm.stopPrank();

    vm.prank(BOB);
    // repay without collat amount
    vm.expectRevert(abi.encodeWithSelector(ILYFFarmFacet.LYFFarmFacet_InvalidAssetTier.selector));
    farmFacet.repayWithCollat(subAccount0, address(isolateToken), address(wethUsdcLPToken), 20 ether);
  }
}
