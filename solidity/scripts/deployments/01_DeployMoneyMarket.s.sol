// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Script, console } from "solidity/tests/utils/Script.sol";
import "solidity/tests/utils/StdJson.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { TripleSlopeModel7 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel7.sol";
import { PancakeswapV2LiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2LiquidationStrategy.sol";
import { PancakeswapV2IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";
import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet {}

contract DeployMoneyMarket is Script {
  using stdJson for string;

  struct DeploymentConfig {
    address wNativeAddress;
    address wNativeRelayer;
  }

  function run() public {
    string memory configFilePath = string.concat(
      vm.projectRoot(),
      string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME"))
    );
    string memory configJson = vm.readFile(configFilePath);
    DeploymentConfig memory config = abi.decode(configJson.parseRaw("deploymentConfig"), (DeploymentConfig));

    vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    // deploy money market
    (address _moneyMarket, LibMoneyMarketDeployment.FacetAddresses memory facetAddresses) = LibMoneyMarketDeployment
      .deployMoneyMarket(config.wNativeAddress, config.wNativeRelayer);
    IMoneyMarket moneyMarket = IMoneyMarket(_moneyMarket);

    // setup oracles

    // setup interest rate models
    address interestRateModel1 = address(new TripleSlopeModel7());
    moneyMarket.setInterestModel(address(0), interestRateModel1);

    // setup ib token
    address ibTokenImplementation = address(new InterestBearingToken());
    moneyMarket.setIbTokenImplementation(ibTokenImplementation);

    // setup liquidation strategies
    address router = address(0);
    address pancakeswapV2LiquidationStrategy = address(new PancakeswapV2LiquidationStrategy(router));
    address pancakeswapV2IbTokenLiquidationStrategy = address(
      new PancakeswapV2IbTokenLiquidationStrategy(router, address(moneyMarket))
    );
    address[] memory liquidationStrats = new address[](2);
    liquidationStrats[0] = pancakeswapV2LiquidationStrategy;
    liquidationStrats[1] = pancakeswapV2IbTokenLiquidationStrategy;
    moneyMarket.setLiquidationStratsOk(liquidationStrats, true);

    // setup fee models
    address feeModel1 = address(new FixedFeeModel());
    moneyMarket.setRepurchaseRewardModel(IFeeModel(feeModel1));

    // set protocol params
    moneyMarket.setTreasury(address(0));

    vm.stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    // money market is top level key
    string memory topLevelKey = "TopLevel";
    vm.serializeAddress(topLevelKey, "MoneyMarketDiamond", address(moneyMarket));

    // steps
    // 1. define object key
    // 2. serialize addresses
    // 3. on final address, save to object string
    // 4. serialize object string to money market key

    // facets
    string memory facetsKey = "FacetAddresses";
    vm.serializeAddress(facetsKey, "DiamondCutFacet", facetAddresses.diamondCutFacet);
    vm.serializeAddress(facetsKey, "DiamondLoupeFacet", facetAddresses.diamondLoupeFacet);
    vm.serializeAddress(facetsKey, "ViewFacet", facetAddresses.viewFacet);
    vm.serializeAddress(facetsKey, "LendFacet", facetAddresses.lendFacet);
    vm.serializeAddress(facetsKey, "CollateralFacet", facetAddresses.collateralFacet);
    vm.serializeAddress(facetsKey, "BorrowFacet", facetAddresses.borrowFacet);
    vm.serializeAddress(facetsKey, "NonCollatBorrowFacet", facetAddresses.nonCollatBorrowFacet);
    vm.serializeAddress(facetsKey, "AdminFacet", facetAddresses.adminFacet);
    vm.serializeAddress(facetsKey, "LiquidationFacet", facetAddresses.liquidationFacet);
    string memory facetsObject = vm.serializeAddress(facetsKey, "OwnershipFacet", facetAddresses.ownershipFacet);
    vm.serializeString(topLevelKey, facetsKey, facetsObject);

    // interest rate models
    string memory interestRateModelsKey = "InterestRateModels";
    string memory interestRateModelsObject = vm.serializeAddress(
      interestRateModelsKey,
      "InterestRateModel1",
      interestRateModel1
    );
    vm.serializeString(topLevelKey, interestRateModelsKey, interestRateModelsObject);

    // liquidation strategies
    string memory liquidationStrategiesKey = "LiquidationStrategies";
    vm.serializeAddress(liquidationStrategiesKey, "PancakeswapV2LiquidationStrategy", pancakeswapV2LiquidationStrategy);
    string memory liquidationStrategiesObject = vm.serializeAddress(
      liquidationStrategiesKey,
      "PancakeswapV2IbTokenLiquidationStrategy",
      pancakeswapV2IbTokenLiquidationStrategy
    );
    vm.serializeString(topLevelKey, liquidationStrategiesKey, liquidationStrategiesObject);

    // fee models
    string memory feeModelsKey = "FeeModels";
    string memory feeModelsObject = vm.serializeAddress(feeModelsKey, "FeeModel1", feeModel1);
    string memory finalJson = vm.serializeString(topLevelKey, feeModelsKey, feeModelsObject);

    // this will overwrite existing json
    vm.writeJson(finalJson, "deployedAddresses.json");
  }
}
