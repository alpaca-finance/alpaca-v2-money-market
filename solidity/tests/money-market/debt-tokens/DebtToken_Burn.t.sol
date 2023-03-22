// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";
import { DebtToken_BaseTest } from "./DebtToken_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

// interfaces
import { IDebtToken } from "../../../contracts/money-market/interfaces/IDebtToken.sol";

contract DebtToken_BurnTest is DebtToken_BaseTest {
  DebtToken internal debtToken;

  function setUp() public override {
    super.setUp();

    debtToken = deployUninitializedDebtToken();
    debtToken.initialize(address(weth), moneyMarketDiamond);

    vm.startPrank(moneyMarketDiamond);
    address[] memory _okHolders = new address[](1);
    _okHolders[0] = address(moneyMarketDiamond);
    debtToken.setOkHolders(_okHolders, true);
    vm.stopPrank();
  }

  function testCorrectness_WhenFullyBurn_ShouldWork() external {
    uint256 _amount = 10 ether;
    uint256 _initialBalance = debtToken.balanceOf(moneyMarketDiamond);

    vm.startPrank(moneyMarketDiamond);
    debtToken.mint(moneyMarketDiamond, _amount);
    debtToken.burn(moneyMarketDiamond, _amount);
    vm.stopPrank();

    assertEq(debtToken.balanceOf(moneyMarketDiamond), _initialBalance);
  }

  function testCorrectness_WhenPartiallyBurn_DebtTokenShouldRemain() external {
    uint256 _amount = 10 ether;
    uint256 _burnAmount = 5 ether;

    vm.startPrank(moneyMarketDiamond);
    debtToken.mint(moneyMarketDiamond, _amount);
    debtToken.burn(moneyMarketDiamond, _burnAmount);
    vm.stopPrank();

    assertEq(debtToken.balanceOf(moneyMarketDiamond), _amount - _burnAmount);
  }

  function testRevert_WhenBurnFromNonOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    debtToken.burn(moneyMarketDiamond, 1 ether);
  }

  function testRevert_WhenBurnFromNonOkHolder() external {
    vm.prank(moneyMarketDiamond);
    vm.expectRevert(IDebtToken.DebtToken_UnApprovedHolder.selector);
    debtToken.burn(ALICE, 1 ether);
  }
}
