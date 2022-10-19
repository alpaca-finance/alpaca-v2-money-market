// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";

contract MoneyMarket_DepositFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserDeposit_TokenShouldSafeTransferFromUserToMM()
    external
  {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    depositFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);

    assertEq(ibWeth.balanceOf(ALICE), 10 ether);
  }

  function testCorrectness_WhenMultipleDeposit_ShouldMintShareCorrectly()
    external
  {
    uint256 _depositAmount1 = 10 ether;
    uint256 _depositAmount2 = 20 ether;
    uint256 _expectedTotalShare = 0;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _depositAmount1);
    depositFacet.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // frist deposit mintShare = depositAmount
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    weth.mint(BOB, _depositAmount2);
    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, _depositAmount2);
    depositFacet.deposit(address(weth), _depositAmount2);
    vm.stopPrank();

    // mintShare = 20 * 10 / 10 = 20
    uint256 _expectedBoBShare = 20 ether;
    _expectedTotalShare += _expectedBoBShare;
    assertEq(ibWeth.balanceOf(BOB), 20 ether);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);
  }

  function testRevert_WhenUserDepositInvalidToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(
        IDepositFacet.DepositFacet_InvalidToken.selector,
        _randomToken
      )
    );
    depositFacet.deposit(_randomToken, 10 ether);
    vm.stopPrank();
  }
}
