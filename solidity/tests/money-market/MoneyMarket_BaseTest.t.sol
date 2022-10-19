// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest } from "../base/BaseTest.sol";

// interfaces
import { IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

abstract contract MoneyMarket_BaseTest is BaseTest {
  address internal moneyMarketDiamond;
  IDepositFacet internal depositFacet;
  IAdminFacet internal adminFacet;

  function setUp() public virtual {
    (moneyMarketDiamond) = deployPoolDiamond();

    depositFacet = IDepositFacet(moneyMarketDiamond);
    adminFacet = IAdminFacet(moneyMarketDiamond);

    weth.mint(ALICE, 1000 ether);

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](1);
    _ibPair[0] = IAdminFacet.IbPair({
      token: address(weth),
      ibToken: address(ibWeth)
    });

    adminFacet.setTokenToIbTokens(_ibPair);
  }
}
