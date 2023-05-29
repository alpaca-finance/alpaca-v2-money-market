// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../../base/BaseTest.sol";

import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { AlpacaV2Oracle02, IAlpacaV2Oracle02 } from "../../../contracts/oracle/AlpacaV2Oracle02.sol";

contract AlpacaV2Oracle02_InitializeTest is BaseTest {
  function setUp() public virtual {}

  function testRevert_WhenbaseStableTokenIsNot18Decimal_ShouldRevert() external {
    MockERC20 aToken = deployMockErc20("aToken", "aToken", 9);

    oracleMedianizer = deployOracleMedianizer();

    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle02.AlpacaV2Oracle02_InvalidBaseStableTokenDecimal.selector));
    new AlpacaV2Oracle02(address(oracleMedianizer), address(aToken), address(usd));
  }
}
