// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { ILendFacet } from "../../contracts/money-market/facets/LendFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_LendFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserDeposit_TokenShouldSafeTransferFromUserToMM()
    external
  {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
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
    lendFacet.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // frist deposit mintShare = depositAmount
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    weth.mint(BOB, _depositAmount2);
    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, _depositAmount2);
    lendFacet.deposit(address(weth), _depositAmount2);
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
        ILendFacet.LendFacet_InvalidToken.selector,
        _randomToken
      )
    );
    lendFacet.deposit(_randomToken, 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserWithdraw_ibTokenShouldBurnedAndTransferTokenToUser()
    external
  {
    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.deposit(address(weth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 990 ether);
    assertEq(weth.balanceOf(moneyMarketDiamond), 10 ether);
    assertEq(ibWeth.balanceOf(ALICE), 10 ether);

    vm.startPrank(ALICE);
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.withdraw(address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(ibWeth.totalSupply(), 0);
    assertEq(ibWeth.balanceOf(ALICE), 0);
    assertEq(weth.balanceOf(ALICE), 1000 ether);
  }

  function testRevert_WhenUserWithdrawInvalidibToken_ShouldRevert() external {
    address _randomToken = address(10);
    vm.startPrank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILendFacet.LendFacet_InvalidToken.selector,
        _randomToken
      )
    );
    lendFacet.withdraw(_randomToken, 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserWithdraw_ShareShouldBurnedAndTransferTokenBackCorrectly()
    external
  {
    uint256 _depositAmount1 = 10 ether;
    uint256 _depositAmount2 = 20 ether;
    uint256 _expectedTotalShare = 0;

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, _depositAmount1);
    lendFacet.deposit(address(weth), _depositAmount1);
    vm.stopPrank();

    // first depositor mintShare = depositAmount = 10
    _expectedTotalShare += _depositAmount1;
    assertEq(ibWeth.balanceOf(ALICE), _depositAmount1);

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, _depositAmount2);
    lendFacet.deposit(address(weth), _depositAmount2);
    vm.stopPrank();

    // mintShare = 20 * 10 / 10 = 20
    uint256 _expectedBoBShare = 20 ether;
    _expectedTotalShare += _expectedBoBShare;
    assertEq(ibWeth.balanceOf(BOB), 20 ether);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);

    // alice withdraw share
    vm.startPrank(ALICE);
    _expectedTotalShare -= 10 ether;
    ibWeth.approve(moneyMarketDiamond, 10 ether);
    lendFacet.withdraw(address(ibWeth), 10 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(ALICE), 1000 ether);
    assertEq(ibWeth.balanceOf(ALICE), 0);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);

    // bob withdraw share
    vm.startPrank(BOB);
    _expectedTotalShare -= 20 ether;
    ibWeth.approve(moneyMarketDiamond, 20 ether);
    lendFacet.withdraw(address(ibWeth), 20 ether);
    vm.stopPrank();

    assertEq(weth.balanceOf(BOB), 1000 ether);
    assertEq(ibWeth.balanceOf(BOB), 0);
    assertEq(ibWeth.totalSupply(), _expectedTotalShare);
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldOpenOncePerToken()
    external
  {
    vm.startPrank(ALICE);
    // should pass when register new token
    address _ibToken = lendFacet.openMarket(address(opm));
    assertEq(IERC20(_ibToken).name(), "Interest Bearing OPM");
    assertEq(IERC20(_ibToken).symbol(), "IBOPM");
    assertEq(IERC20(_ibToken).decimals(), 9);

    vm.expectRevert(
      abi.encodeWithSelector(
        ILendFacet.LendFacet_InvalidToken.selector,
        address(opm)
      )
    );
    lendFacet.openMarket(address(opm));

    // able to deposit
    lendFacet.deposit(address(opm), 5 ether);
    assertEq(IERC20(_ibToken).balanceOf(ALICE), 5 ether);
    vm.stopPrank();
  }
}
