// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest } from "../base/BaseTest.sol";

// interfaces
import { IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract MoneyMarket_BaseTest is BaseTest {
  address internal moneyMarketDiamond;
  IDepositFacet internal depositFacet;

  function setUp() public virtual {
    (moneyMarketDiamond) = deployPoolDiamond();

    depositFacet = IDepositFacet(moneyMarketDiamond);

    weth.mint(ALICE, 1000 ether);
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
  }
}
