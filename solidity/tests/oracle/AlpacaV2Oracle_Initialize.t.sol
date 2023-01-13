// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console, MockERC20 } from "../base/BaseTest.sol";

import { OracleMedianizer } from "../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { IAlpacaV2Oracle } from "../../contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { AlpacaV2Oracle } from "../../contracts/oracle/AlpacaV2Oracle.sol";
import { IRouterLike } from "../../contracts/oracle/interfaces/IRouterLike.sol";

contract AlpacaV2Oracle_InitializeTest is BaseTest {
  function setUp() public virtual {}

  function testRevert_WhenbaseStableTokenIsNot18Decimal_ShouldRevert() external {
    MockERC20 aToken = deployMockErc20("aToken", "aToken", 9);

    oracleMedianizer = deployOracleMedianizer();

    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_InvalidBaseStableTokenDecimal.selector));
    new AlpacaV2Oracle(address(oracleMedianizer), address(aToken), address(usd));
  }
}
