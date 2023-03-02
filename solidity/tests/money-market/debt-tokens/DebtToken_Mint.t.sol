// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "../MoneyMarket_BaseTest.t.sol";
import { DebtToken_BaseTest } from "./DebtToken_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

// interfaces
import { IDebtToken } from "../../../contracts/money-market/interfaces/IDebtToken.sol";

contract DebtToken_MintTest is DebtToken_BaseTest {
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

  function testCorrectness_WhenMint_ShouldWork() external {
    uint256 _mintedAmount = 10 ether;

    vm.startPrank(moneyMarketDiamond);
    debtToken.mint(moneyMarketDiamond, _mintedAmount);
    debtToken.approve(moneyMarketDiamond, _mintedAmount);

    assertEq(debtToken.balanceOf(moneyMarketDiamond), _mintedAmount);
    assertEq(debtToken.totalSupply(), _mintedAmount);
    vm.stopPrank();
  }

  function testRevert_WhenMintToNonOkHolder() external {
    vm.prank(moneyMarketDiamond);
    vm.expectRevert(IDebtToken.DebtToken_UnApprovedHolder.selector);
    debtToken.mint(ALICE, 1 ether);
  }

  function testRevert_WhenMintFromNonOwner() external {
    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    debtToken.mint(moneyMarketDiamond, 1 ether);
  }
}
