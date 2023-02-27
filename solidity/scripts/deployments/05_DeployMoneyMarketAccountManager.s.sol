// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";
import { MoneyMarketAccountManager } from "solidity/contracts/account-manager/MoneyMarketAccountManager.sol";
import { MockWNativeRelayer } from "solidity/tests/mocks/MockWNativeRelayer.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployMoneyMarketAccountManagerScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // open market for wNativeToken
    IAdminFacet.TokenConfigInput memory tokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.CROSS,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 0
    });
    IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    address ibWNative = moneyMarket.openMarket(wNativeToken, tokenConfigInput, ibTokenConfigInput);
    _writeJson(vm.toString(address(ibWNative)), ".ibTokens.ibBnb");

    // deploy implementation
    address accountManagerImplementation = address(new MoneyMarketAccountManager());

    // deploy proxy
    bytes memory data = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address)")),
      address(moneyMarket),
      wNativeToken,
      nativeRelayer
    );
    address accountManagerProxy = address(
      new TransparentUpgradeableProxy(accountManagerImplementation, proxyAdminAddress, data)
    );

    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = accountManagerProxy;

    moneyMarket.setAccountManagersOk(_accountManagers, true);

    _stopBroadcast();

    _writeJson(vm.toString(accountManagerImplementation), ".moneyMarket.accountManager.implementation");
    _writeJson(vm.toString(accountManagerProxy), ".moneyMarket.accountManager.proxy");
  }
}
