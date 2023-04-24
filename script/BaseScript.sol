// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "solidity/tests/utils/StdJson.sol";
import { Script, console } from "solidity/tests/utils/Script.sol";

// libs
import { LibMoneyMarketDeployment } from "./deployments/libraries/LibMoneyMarketDeployment.sol";

// interfaces
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";
import { ICollateralFacet } from "solidity/contracts/money-market/interfaces/ICollateralFacet.sol";
import { IBorrowFacet } from "solidity/contracts/money-market/interfaces/IBorrowFacet.sol";
import { ILendFacet } from "solidity/contracts/money-market/interfaces/ILendFacet.sol";
import { IMMOwnershipFacet } from "solidity/contracts/money-market/interfaces/IMMOwnershipFacet.sol";
import { IMiniFL } from "solidity/contracts/miniFL/interfaces/IMiniFL.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet, ICollateralFacet, IBorrowFacet, ILendFacet, IMMOwnershipFacet {}

abstract contract BaseScript is Script {
  using stdJson for string;

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  IMoneyMarket internal moneyMarket;
  IMiniFL internal miniFL;
  IMoneyMarketAccountManager internal accountManager;
  address internal deployerAddress;
  address internal userAddress;
  address internal proxyAdminAddress;
  address internal nativeRelayer;
  address internal chainlinkOracle;
  address internal oracleMedianizer;
  address internal usdPlaceholder;
  address internal ibTokenImplementation;
  address internal debtTokenImplementation;
  address internal pancakeswapV2LiquidateStrat;
  address internal pancakeswapV2IbLiquidateStrat;
  address internal pancakeswapV3IbLiquidateStrat;
  IAlpacaV2Oracle internal alpacaV2Oracle;
  address internal pancakeswapFactoryV3;
  address internal pancakeswapRouterV2;
  address internal pancakeswapRouterV3;
  IFeeModel internal repurchaseRewardModel;

  address internal ada;
  address internal alpaca;
  address internal btcb;
  address internal busd;
  address internal cake;
  address internal dodo;
  address internal doge;
  address internal dot;
  address internal eth;
  address internal matic;
  address internal tusd;
  address internal usdt;
  address internal usdc;
  address internal wbnb;
  address internal xrp;

  constructor() {
    deployerAddress = vm.addr(deployerPrivateKey);

    string memory configJson = vm.readFile(configFilePath);
    moneyMarket = abi.decode(configJson.parseRaw(".moneyMarket.moneyMarketDiamond"), (IMoneyMarket));
    proxyAdminAddress = abi.decode(configJson.parseRaw(".proxyAdmin"), (address));
    miniFL = abi.decode(configJson.parseRaw(".miniFL.proxy"), (IMiniFL));
    accountManager = abi.decode(configJson.parseRaw(".moneyMarket.accountManager.proxy"), (IMoneyMarketAccountManager));
    nativeRelayer = abi.decode(configJson.parseRaw(".nativeRelayer"), (address));
    usdPlaceholder = abi.decode(configJson.parseRaw(".usdPlaceholder"), (address));

    pancakeswapFactoryV3 = abi.decode(configJson.parseRaw(".yieldSources.pancakeSwap.factoryV3"), (address));
    pancakeswapRouterV2 = abi.decode(configJson.parseRaw(".yieldSources.pancakeSwap.routerV2"), (address));
    pancakeswapRouterV3 = abi.decode(configJson.parseRaw(".yieldSources.pancakeSwap.routerV3"), (address));
    repurchaseRewardModel = abi.decode(configJson.parseRaw(".sharedConfig.fixedRepurchaseRewardModel"), (IFeeModel));

    ibTokenImplementation = abi.decode(
      configJson.parseRaw(".moneyMarket.interestBearingTokenImplementation"),
      (address)
    );
    debtTokenImplementation = abi.decode(configJson.parseRaw(".moneyMarket.debtTokenImplementation"), (address));
    pancakeswapV2LiquidateStrat = abi.decode(
      configJson.parseRaw(".sharedStrategies.pancakeswap.strategyLiquidate"),
      (address)
    );
    pancakeswapV2IbLiquidateStrat = abi.decode(
      configJson.parseRaw(".sharedStrategies.pancakeswap.strategyLiquidateIb"),
      (address)
    );
    pancakeswapV3IbLiquidateStrat = abi.decode(
      configJson.parseRaw(".sharedStrategies.pancakeswap.strategyLiquidateIbV3"),
      (address)
    );

    // oracles
    chainlinkOracle = abi.decode(configJson.parseRaw(".oracle.chainlinkOracle"), (address));
    oracleMedianizer = abi.decode(configJson.parseRaw(".oracle.oracleMedianizer"), (address));
    alpacaV2Oracle = abi.decode(configJson.parseRaw(".oracle.alpacaV2Oracle"), (IAlpacaV2Oracle));

    // tokens
    ada = abi.decode(configJson.parseRaw(".tokens.ada"), (address));
    alpaca = abi.decode(configJson.parseRaw(".tokens.alpaca"), (address));
    btcb = abi.decode(configJson.parseRaw(".tokens.btcb"), (address));
    busd = abi.decode(configJson.parseRaw(".tokens.busd"), (address));
    cake = abi.decode(configJson.parseRaw(".tokens.cake"), (address));
    dodo = abi.decode(configJson.parseRaw(".tokens.dodo"), (address));
    doge = abi.decode(configJson.parseRaw(".tokens.doge"), (address));
    dot = abi.decode(configJson.parseRaw(".tokens.dot"), (address));
    eth = abi.decode(configJson.parseRaw(".tokens.eth"), (address));
    matic = abi.decode(configJson.parseRaw(".tokens.matic"), (address));
    tusd = abi.decode(configJson.parseRaw(".tokens.tusd"), (address));
    usdt = abi.decode(configJson.parseRaw(".tokens.usdt"), (address));
    usdc = abi.decode(configJson.parseRaw(".tokens.usdc"), (address));
    wbnb = abi.decode(configJson.parseRaw(".tokens.wbnb"), (address));
    xrp = abi.decode(configJson.parseRaw(".tokens.xrp"), (address));
  }

  function _startDeployerBroadcast() internal {
    _startBroadcast(deployerPrivateKey);
  }

  function _startBroadcast(uint256 pK) internal {
    console.log("");

    try vm.envAddress("IMPERSONATE_AS") returns (address _impersonatedAs) {
      console.log("==== start broadcast impersonated as: ", _impersonatedAs);
      vm.startBroadcast(_impersonatedAs);
    } catch {
      console.log("==== start broadcast as: ", vm.addr(pK));
      vm.startBroadcast(pK);
    }
  }

  function _stopBroadcast() internal {
    vm.stopBroadcast();
    console.log("==== broadcast stopped ====\n");
  }

  function _writeJson(string memory serializedJson, string memory path) internal {
    console.log("writing to:", path, "value:", serializedJson);
    serializedJson.write(configFilePath, path);
  }
}
