// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { FixedInterestRateModel, IInterestRateModel } from "../../contracts/money-market/interest-models/FixedInterestRateModel.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

contract MoneyMarket_AccrueInterest_TransferCollatertalTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    FixedInterestRateModel model = new FixedInterestRateModel(wethDecimal);
    TripleSlopeModel6 tripleSlope6 = new TripleSlopeModel6();
    adminFacet.setInterestModel(address(weth), address(model));
    adminFacet.setInterestModel(address(usdc), address(tripleSlope6));
    adminFacet.setInterestModel(address(isolateToken), address(model));

    vm.startPrank(ALICE);
    lendFacet.deposit(ALICE, address(weth), 50 ether);
    lendFacet.deposit(ALICE, address(btc), 100 ether);
    lendFacet.deposit(ALICE, address(usdc), normalizeEther(20 ether, usdcDecimal));
    lendFacet.deposit(ALICE, address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokenAndTransferCollateral_ShouldaccrueInterestForAllBorrowedToken()
    external
  {
    // ALICE add collateral
    uint256 _wethBorrowAmount = 10 ether;
    uint256 _usdcBorrowAmount = normalizeEther(10 ether, usdcDecimal);

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), _wethBorrowAmount * 2);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), _usdcBorrowAmount * 2);
    vm.stopPrank();

    // BOB borrow
    vm.startPrank(ALICE);
    borrowFacet.borrow(subAccount0, address(weth), _wethBorrowAmount);
    borrowFacet.borrow(subAccount0, address(usdc), _usdcBorrowAmount);
    vm.stopPrank();

    // time past
    vm.warp(block.timestamp + 100);

    vm.startPrank(ALICE);
    // transfer collateral will trigger accrue interest on all borrowed token
    collateralFacet.transferCollateral(0, 1, address(weth), 0);
    vm.stopPrank();

    // assert ALICE
    (, uint256 _aliceActualWethDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(
      ALICE,
      subAccount0,
      address(weth)
    );
    (, uint256 _aliceActualUSDCDebtAmount) = viewFacet.getOverCollatDebtShareAndAmountOf(
      ALICE,
      subAccount0,
      address(usdc)
    );

    assertGt(_aliceActualWethDebtAmount, _wethBorrowAmount);
    assertGt(_aliceActualUSDCDebtAmount, _usdcBorrowAmount);

    //assert Global
    assertGt(viewFacet.getOverCollatTokenDebtValue(address(weth)), _wethBorrowAmount);
    assertGt(viewFacet.getOverCollatTokenDebtValue(address(usdc)), _usdcBorrowAmount);
  }
}
