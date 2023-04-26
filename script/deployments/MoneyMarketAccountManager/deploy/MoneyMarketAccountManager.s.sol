// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { MoneyMarketAccountManager } from "solidity/contracts/account-manager/MoneyMarketAccountManager.sol";
import { MockWNativeRelayer } from "solidity/tests/mocks/MockWNativeRelayer.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMoneyMarketAccountManagerScript is BaseScript {
  using stdJson for string;

  function run() public {
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    _startDeployerBroadcast();
    // deploy implementation
    address accountManagerImplementation = address(new MoneyMarketAccountManager());

    // deploy proxy
    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      address(moneyMarket),
      wbnb,
      nativeRelayer
    );
    address accountManagerProxy = address(
      new TransparentUpgradeableProxy(accountManagerImplementation, proxyAdminAddress, data)
    );

    _stopBroadcast();

    _writeJson(vm.toString(accountManagerImplementation), ".moneyMarket.accountManager.implementation");
    _writeJson(vm.toString(accountManagerProxy), ".moneyMarket.accountManager.proxy");
  }
}
