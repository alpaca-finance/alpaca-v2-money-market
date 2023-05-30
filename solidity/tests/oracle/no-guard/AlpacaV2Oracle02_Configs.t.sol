// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../../base/BaseTest.sol";

import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { AlpacaV2Oracle02, IAlpacaV2Oracle02 } from "../../../contracts/oracle/AlpacaV2Oracle02.sol";
import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

contract AlpacaV2Oracle02_Configs is BaseTest {
  address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
  address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
  address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
  address constant BTC = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;

  function setUp() public virtual {
    vm.createSelectFork("https://bsc-dataseed3.defibit.io", 27_280_390);
    oracleMedianizer = deployOracleMedianizer();
    alpacaV2Oracle02 = new AlpacaV2Oracle02(address(oracleMedianizer), usd);
  }

  function testCorrectness_Settings_ShouldWork() external {
    // Create new oracleMedianizer
    OracleMedianizer _newOracleMedianizer = deployOracleMedianizer();
    vm.mockCall(
      address(_newOracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, WBNB, usd),
      abi.encode(1e18, block.timestamp)
    );

    // set default oracle
    alpacaV2Oracle02.setDefaultOracle(address(_newOracleMedianizer));
    assertEq(alpacaV2Oracle02.oracle(), address(_newOracleMedianizer));

    // Create new specific oracle
    OracleMedianizer _newSpecificOracleMedianizer = deployOracleMedianizer();
    vm.mockCall(
      address(_newSpecificOracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, BTC, usd),
      abi.encode(1e18, block.timestamp)
    );
    IAlpacaV2Oracle02.SpecificOracle[] memory _inputs = new IAlpacaV2Oracle02.SpecificOracle[](1);
    _inputs[0] = IAlpacaV2Oracle02.SpecificOracle({
      token: address(BTC),
      oracle: address(_newSpecificOracleMedianizer)
    });

    // set specific oracle
    alpacaV2Oracle02.setSpecificOracle(_inputs);
    assertEq(alpacaV2Oracle02.specificOracles(address(BTC)), address(_newSpecificOracleMedianizer));
  }

  // unauthorzied set
  function testRevert_Unauthorized() external {
    address _oracle = makeAddr("oracle");
    IAlpacaV2Oracle02.SpecificOracle[] memory _inputs = new IAlpacaV2Oracle02.SpecificOracle[](1);
    _inputs[0] = IAlpacaV2Oracle02.SpecificOracle({ token: address(USDT), oracle: _oracle });

    vm.startPrank(ALICE);

    vm.expectRevert("Ownable: caller is not the owner");
    alpacaV2Oracle02.setDefaultOracle(_oracle);

    vm.expectRevert("Ownable: caller is not the owner");
    alpacaV2Oracle02.setSpecificOracle(_inputs);

    vm.stopPrank();
  }
}
