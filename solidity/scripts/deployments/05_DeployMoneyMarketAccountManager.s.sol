// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";
import { MoneyMarketAccountManager } from "solidity/contracts/account-manager/MoneyMarketAccountManager.sol";
import { MockWNativeRelayer } from "solidity/tests/mocks/MockWNativeRelayer.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";

contract DeployMoneyMarketAccountManagerScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // deploy nativeRelayer
    // NOTE: remove this in prod
    nativeRelayer = address(new MockWNativeRelayer(wNativeToken));

    // TODO: consider moving this somewhere else
    // set implementation before open market
    moneyMarket.setIbTokenImplementation(address(new InterestBearingToken()));
    moneyMarket.setDebtTokenImplementation(address(new DebtToken()));

    // open market for wNativeToken
    IAdminFacet.TokenConfigInput memory tokenConfigInput = IAdminFacet.TokenConfigInput({
      token: wNativeToken,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    moneyMarket.openMarket(wNativeToken, tokenConfigInput, tokenConfigInput);

    accountManager = new MoneyMarketAccountManager(address(moneyMarket), wNativeToken, nativeRelayer);

    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = address(accountManager);

    moneyMarket.setAccountManagersOk(_accountManagers, true);

    _stopBroadcast();

    _writeJson(vm.toString(address(accountManager)), ".moneyMarket.accountManager");
    _writeJson(vm.toString(address(nativeRelayer)), ".nativeRelayer");
  }
}
