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

  function testCorrectness_WhenUserRepay_SubaccountDebtShouldDecrease() external {
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
    vm.warp(block.timestamp + 10);

    // timepast * interest rate * debt value = 10 * 0.01 * 20 = 2
    assertEq(
      viewFacet.getPendingInterest(address(weth), address(wethUsdcLPToken)),
      2 ether,
      "expected interest is not match"
    );

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
    assertEq(_bobDebtShare, 15 ether, "expected debt shares is mismatch"); // 20 - 5 = 15
    assertEq(_bobDebtValue, 16.5 ether, "expected debt value is mismatch"); // 22 - 5.5 = 16.5

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
}
