// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

contract MoneyMarket_Flashloan is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }
}
