// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "solidity/tests/utils/StdJson.sol";
import { Script, console } from "solidity/tests/utils/Script.sol";

// libs
import { LibMoneyMarketDeployment } from "../deployments/libraries/LibMoneyMarketDeployment.sol";

// interfaces
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";
import { ICollateralFacet } from "solidity/contracts/money-market/interfaces/ICollateralFacet.sol";
import { IBorrowFacet } from "solidity/contracts/money-market/interfaces/IBorrowFacet.sol";
import { ILendFacet } from "solidity/contracts/money-market/interfaces/ILendFacet.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet, ICollateralFacet, IBorrowFacet, ILendFacet {}

/// @dev DEPRECATED pls use BaseScript
abstract contract BaseUtilsScript is Script {
  using stdJson for string;

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  IMoneyMarket internal moneyMarket;
  address internal deployerAddress;
  address internal userAddress;

  struct MoneyMarketConfig {
    address MoneyMarketDiamond;
  }

  function run() public {
    _setUp();
    _run();
  }

  //
  // setups
  //

  /// @dev setUp for actual script runs, use deployed mm address
  function _setUp() internal {
    MoneyMarketConfig memory mmConfig = _getConfig();
    moneyMarket = IMoneyMarket(mmConfig.MoneyMarketDiamond);
    deployerAddress = vm.addr(deployerPrivateKey);
    console.log("addresses");
    console.log("  deployer     :", deployerAddress);
    console.log("  user     :", userAddress);
    console.log("  money market :", address(moneyMarket));
  }

  function _setUpMockToken() internal returns (address) {
    return address(new MockERC20("", "TEST", 18));
  }

  //
  // utilities
  //

  function _getConfig() internal view returns (MoneyMarketConfig memory) {
    console.log("load config file from", configFilePath);
    string memory configJson = vm.readFile(configFilePath);
    return abi.decode(configJson.parseRaw("MoneyMarket"), (MoneyMarketConfig));
  }

  function _startDeployerBroadcast() internal {
    vm.startBroadcast(deployerPrivateKey);
    console.log("");
    console.log("==== start broadcast as deployer ====");
  }

  function _stopBroadcast() internal {
    vm.stopBroadcast();
    console.log("==== broadcast stopped ====\n");
  }

  function _run() internal virtual;
}
