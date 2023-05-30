// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../../base/BaseTest.sol";

import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { AlpacaV2Oracle02, IAlpacaV2Oracle02 } from "../../../contracts/oracle/AlpacaV2Oracle02.sol";

contract AlpacaV2Oracle02_GetPrice is BaseTest {
  address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
  address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
  address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
  address constant BTC = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
  uint256 constant tokenPrice = 1e18;

  OracleMedianizer oracleMedianizer2;

  function setUp() public virtual {
    vm.createSelectFork("https://bsc-dataseed3.defibit.io", 27_280_390);
    oracleMedianizer = deployOracleMedianizer();
    oracleMedianizer2 = deployOracleMedianizer();
    alpacaV2Oracle02 = new AlpacaV2Oracle02(address(oracleMedianizer), usd);
  }

  // test get price from default oracle
  function testCorrectness_GetPrice() external {
    // Mock call oracle return price
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, WBNB, usd),
      abi.encode(tokenPrice, block.timestamp)
    );
    vm.mockCall(
      address(oracleMedianizer2),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, BTC, usd),
      abi.encode(tokenPrice, block.timestamp)
    );

    // set token price on specified oracle
    IAlpacaV2Oracle02.SpecificOracle[] memory _inputs = new IAlpacaV2Oracle02.SpecificOracle[](1);
    _inputs[0] = IAlpacaV2Oracle02.SpecificOracle({ token: BTC, oracle: address(oracleMedianizer2) });

    alpacaV2Oracle02.setSpecificOracle(_inputs);

    (uint256 _wbnbPrice, ) = alpacaV2Oracle02.getTokenPrice(WBNB);

    // get token price from default oracle
    assertEq(_wbnbPrice, tokenPrice);

    (uint256 _btcPrice, ) = alpacaV2Oracle02.getTokenPrice(BTC);

    // get token price from specified oracle
    assertEq(_btcPrice, tokenPrice);

    // get unset token price, should revert
    vm.expectRevert();
    alpacaV2Oracle02.getTokenPrice(USDT);
  }
}
