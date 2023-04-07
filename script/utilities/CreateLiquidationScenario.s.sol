// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../BaseScript.sol";

// import { SimplePriceOracle } from "solidity/contracts/oracle/SimplePriceOracle.sol";
// import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { MockAlpacaV2Oracle } from "solidity/tests/mocks/MockAlpacaV2Oracle.sol";

contract CreateLiquidationScenarioScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // address implementation = address(new SimplePriceOracle());
    // bytes memory data = abi.encodeWithSelector(bytes4(keccak256("initialize(address)")), deployerAddress);
    // SimplePriceOracle oracle = SimplePriceOracle(
    //   address(new TransparentUpgradeableProxy(implementation, proxyAdminAddress, data))
    // );

    // address[] memory token0s = new address[](1);
    // token0s[0] = wbnb;
    // address[] memory token1s = new address[](1);
    // token1s[0] = usdPlaceholder;
    // uint256[] memory prices = new uint256[](1);
    // prices[0] = 500 ether; // current bnb @311
    // oracle.setPrices(token0s, token1s, prices);

    // alpacaV2Oracle.setOracle(address(oracle));

    MockAlpacaV2Oracle oracle = new MockAlpacaV2Oracle();
    oracle.setTokenPrice(wbnb, 500 ether);
    oracle.setTokenPrice(ibBnb, 500 ether);
    oracle.setTokenPrice(busd, 1 ether);
    oracle.setTokenPrice(ibBusd, 1 ether);
    oracle.setTokenPrice(usdt, 1 ether);
    oracle.setTokenPrice(doge, 0.8 ether);
    oracle.setTokenPrice(ibDoge, 0.8 ether);
    oracle.setTokenPrice(dodo, 0.3 ether);
    oracle.setTokenPrice(ibDodo, 0.3 ether);

    moneyMarket.setOracle(address(oracle));

    _stopBroadcast();
  }
}
