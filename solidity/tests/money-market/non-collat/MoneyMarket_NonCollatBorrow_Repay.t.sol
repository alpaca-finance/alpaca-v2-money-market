// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";

// interfaces
import { INonCollatBorrowFacet, LibDoublyLinkedList } from "../../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { IBorrowFacet } from "../../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

contract MoneyMarket_NonCollatBorrow_RepayTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    adminFacet.setNonCollatBorrowerOk(ALICE, true);
    adminFacet.setNonCollatBorrowerOk(BOB, true);

    vm.startPrank(ALICE);
    lendFacet.deposit(ALICE, address(weth), normalizeEther(50 ether, wethDecimal));
    lendFacet.deposit(ALICE, address(usdc), normalizeEther(20 ether, usdcDecimal));
    lendFacet.deposit(ALICE, address(btc), normalizeEther(20 ether, btcDecimal));
    lendFacet.deposit(ALICE, address(cake), normalizeEther(20 ether, cakeDecimal));
    lendFacet.deposit(ALICE, address(isolateToken), normalizeEther(20 ether, isolateTokenDecimal));
    vm.stopPrank();
  }

  function testCorrectness_WhenUserRepayLessThanDebtHeHad_ShouldWork() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceRepayAmount = 5 ether;

    uint256 _bobBorrowAmount = 20 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    nonCollatBorrowFacet.nonCollatRepay(ALICE, address(weth), 5 ether);

    vm.stopPrank();

    vm.startPrank(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _bobBorrowAmount);

    vm.stopPrank();

    uint256 _aliceRemainingDebt = viewFacet.getNonCollatAccountDebt(ALICE, address(weth));

    assertEq(_aliceRemainingDebt, _aliceBorrowAmount - _aliceRepayAmount);

    uint256 _tokenDebt = viewFacet.getNonCollatTokenDebt(address(weth));

    assertEq(_tokenDebt, (_aliceBorrowAmount + _bobBorrowAmount) - _aliceRepayAmount);
  }

  function testCorrectness_WhenUserOverRepay_ShouldOnlyRepayTheDebtHeHad() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceRepayAmount = 15 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    nonCollatBorrowFacet.nonCollatRepay(ALICE, address(weth), _aliceRepayAmount);
    uint256 _aliceWethBalanceAfter = weth.balanceOf(ALICE);
    vm.stopPrank();

    uint256 _aliceRemainingDebt = viewFacet.getNonCollatAccountDebt(ALICE, address(weth));

    assertEq(_aliceRemainingDebt, 0);

    assertEq(_aliceWethBalanceBefore - _aliceWethBalanceAfter, _aliceBorrowAmount);

    uint256 _tokenDebt = viewFacet.getNonCollatTokenDebt(address(weth));

    assertEq(_tokenDebt, 0);
  }
}
