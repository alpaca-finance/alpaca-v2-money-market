// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// contracts
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../../contracts/money-market/facets/AdminFacet.sol";

contract InterestBearingToken_HooksTest is MoneyMarket_BaseTest {
  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
  event Withdraw(
    address indexed caller,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  InterestBearingToken internal ibToken;

  function setUp() public override {
    super.setUp();

    ibToken = new InterestBearingToken();
    ibToken.initialize(address(weth), moneyMarketDiamond);
  }

  function testCorrectness_WhenCallOnDeposit_ShouldMintSharesAndEmitEvent() external {
    uint256 _shareToMint = 2 ether;

    vm.prank(moneyMarketDiamond);
    vm.expectEmit(true, true, false, false, address(ibToken));
    emit Deposit(moneyMarketDiamond, BOB, 1 ether, _shareToMint);
    ibToken.onDeposit(BOB, 1 ether, _shareToMint);

    assertEq(ibToken.balanceOf(BOB), _shareToMint);
  }

  function testCorrectness_WhenCallOnWithdraw_ShouldBurnSharesAndEmitEvent() external {
    uint256 _shareAmount = 1 ether;

    vm.startPrank(moneyMarketDiamond);
    ibToken.onDeposit(BOB, 0, _shareAmount);

    assertEq(ibToken.balanceOf(BOB), _shareAmount);

    vm.expectEmit(true, true, false, false, address(ibToken));
    emit Withdraw(moneyMarketDiamond, ALICE, BOB, 0, _shareAmount);
    ibToken.onWithdraw(BOB, ALICE, 0, _shareAmount);

    assertEq(ibToken.balanceOf(BOB), 0);
  }

  function testRevert_WhenCallOnDepositCallerIsNotOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    ibToken.onDeposit(ALICE, 0, 0);
  }

  function testRevert_WhenCallOnWithdrawCallerIsNotOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    ibToken.onWithdraw(ALICE, ALICE, 0, 0);
  }
}
