// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-models/FixedInterestRateModel.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

contract MoneyMarket_AccrueInterest_RemoveCollateralTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    FixedInterestRateModel model = new FixedInterestRateModel();
    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));
    adminFacet.setInterestModel(address(isolateToken), address(model));

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(btc), 100 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokenAndRemoveCollateral_ShouldaccrueInterestForAllBorrowedToken()
    external
  {
    // ALICE add collateral
    uint256 _borrowAmount = 10 ether;

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _borrowAmount * 2);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _borrowAmount * 2);
    vm.stopPrank();

    // BOB borrow
    vm.startPrank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), _borrowAmount);
    borrowFacet.borrow(subAccount0, address(usdc), _borrowAmount);
    vm.stopPrank();

    // time past
    vm.warp(block.timestamp + 10);

    vm.startPrank(ALICE);
    // remove collateral will trigger accrue interest on all borrowed token
    collateralFacet.removeCollateral(subAccount0, address(weth), 0);
    vm.stopPrank();

    // assert ALICE
    (, uint256 _aliceActualWethDebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(weth));
    (, uint256 _aliceActualUSDCDebtAmount) = viewFacet.getOverCollatSubAccountDebt(ALICE, subAccount0, address(usdc));

    assertGt(_aliceActualWethDebtAmount, _borrowAmount);
    assertGt(_aliceActualUSDCDebtAmount, _borrowAmount);

    //assert Global
    assertGt(viewFacet.getOverCollatDebtValue(address(weth)), _borrowAmount);
    assertGt(viewFacet.getOverCollatDebtValue(address(usdc)), _borrowAmount);
  }
}
