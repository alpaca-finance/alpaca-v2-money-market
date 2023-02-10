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

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  struct DeploymentConfig {
    address wNativeAddress;
    address wNativeRelayer;
    address miniFLAddress;
  }

  function run() public {
    string memory configJson = vm.readFile(configFilePath);
    DeploymentConfig memory config = abi.decode(configJson.parseRaw("DeploymentConfig"), (DeploymentConfig));

    vm.startBroadcast(deployerPrivateKey);
    // deploy money market
    (address _moneyMarket, LibMoneyMarketDeployment.FacetAddresses memory facetAddresses) = LibMoneyMarketDeployment
      .deployMoneyMarketDiamond(config.wNativeAddress, config.wNativeRelayer, config.miniFLAddress);
    IMoneyMarket moneyMarket = IMoneyMarket(_moneyMarket);

    // setup oracles

    // setup interest rate models
    address interestRateModel1 = address(new TripleSlopeModel7());
    moneyMarket.setInterestModel(address(0), interestRateModel1);

    // setup ib token
    address ibTokenImplementation = address(new InterestBearingToken());
    moneyMarket.setIbTokenImplementation(ibTokenImplementation);

    // setup debt token
    address debtTokenImplementation = address(new InterestBearingToken());
    moneyMarket.setDebtTokenImplementation(debtTokenImplementation);

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
    // moneyMarket.setTreasury(address(0));

    vm.stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    // money market
    string memory moneyMarketJson = "MoneyMarket";
    moneyMarketJson.serialize("MoneyMarketDiamond", address(moneyMarket));

    // facets
    string memory facetsJson = "Facets";
    facetsJson.serialize("DiamondCutFacet", facetAddresses.diamondCutFacet);
    facetsJson.serialize("DiamondLoupeFacet", facetAddresses.diamondLoupeFacet);
    facetsJson.serialize("ViewFacet", facetAddresses.viewFacet);
    facetsJson.serialize("LendFacet", facetAddresses.lendFacet);
    facetsJson.serialize("CollateralFacet", facetAddresses.collateralFacet);
    facetsJson.serialize("BorrowFacet", facetAddresses.borrowFacet);
    facetsJson.serialize("NonCollatBorrowFacet", facetAddresses.nonCollatBorrowFacet);
    facetsJson.serialize("AdminFacet", facetAddresses.adminFacet);
    facetsJson.serialize("LiquidationFacet", facetAddresses.liquidationFacet);
    facetsJson = facetsJson.serialize("OwnershipFacet", facetAddresses.ownershipFacet);
    moneyMarketJson.serialize("Facets", facetsJson);

    // interest rate models
    string memory interestRateModelsJson = "InterestRateModels";
    interestRateModelsJson = interestRateModelsJson.serialize("InterestRateModel1", interestRateModel1);
    moneyMarketJson.serialize("InterestRateModels", interestRateModelsJson);

    // liquidation strategies
    string memory liquidationStrategiesJson = "LiquidationStrategies";
    liquidationStrategiesJson.serialize("PancakeswapV2LiquidationStrategy", pancakeswapV2LiquidationStrategy);
    liquidationStrategiesJson = liquidationStrategiesJson.serialize(
      "PancakeswapV2IbTokenLiquidationStrategy",
      pancakeswapV2IbTokenLiquidationStrategy
    );
    moneyMarketJson.serialize("LiquidationStrategies", liquidationStrategiesJson);

    // fee models
    string memory feeModelsJson = "FeeModels";
    feeModelsJson = feeModelsJson.serialize("FeeModel1", feeModel1);
    moneyMarketJson = moneyMarketJson.serialize("FeeModels", feeModelsJson);

    // this will overwrite MoneyMarket key in config file
    moneyMarketJson.write(configFilePath, ".MoneyMarket");
  }
}
