// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "solidity/tests/utils/StdJson.sol";
import "../BaseScript.sol";

import { LibMoneyMarketDeployment } from "./libraries/LibMoneyMarketDeployment.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";
import { TripleSlopeModel7 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel7.sol";
import { PancakeswapV2LiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2LiquidationStrategy.sol";
import { PancakeswapV2IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";
import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";

contract DeployMoneyMarketScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    // deploy money market
    (address _moneyMarket, LibMoneyMarketDeployment.FacetAddresses memory facetAddresses) = LibMoneyMarketDeployment
      .deployMoneyMarketDiamond(address(miniFL));
    moneyMarket = IMoneyMarket(_moneyMarket);

    // whitelist mm on miniFL to be able to openMarket
    address[] memory _callers = new address[](1);
    _callers[0] = address(moneyMarket);
    miniFL.setWhitelistedCallers(_callers, true);

    // set implementation to be able to open market
    moneyMarket.setIbTokenImplementation(address(new InterestBearingToken()));
    moneyMarket.setDebtTokenImplementation(address(new DebtToken()));

    // setup oracles

    // // setup interest rate models
    // address interestRateModel1 = address(new TripleSlopeModel7());
    // moneyMarket.setInterestModel(address(0), interestRateModel1);

    // // setup ib token
    // address ibTokenImplementation = address(new InterestBearingToken());
    // moneyMarket.setIbTokenImplementation(ibTokenImplementation);

    // // setup debt token
    // address debtTokenImplementation = address(new InterestBearingToken());
    // moneyMarket.setDebtTokenImplementation(debtTokenImplementation);

    // // setup liquidation strategies
    // address router = address(0);
    // address pancakeswapV2LiquidationStrategy = address(new PancakeswapV2LiquidationStrategy(router));
    // address pancakeswapV2IbTokenLiquidationStrategy = address(
    //   new PancakeswapV2IbTokenLiquidationStrategy(router, address(moneyMarket))
    // );
    // address[] memory liquidationStrats = new address[](2);
    // liquidationStrats[0] = pancakeswapV2LiquidationStrategy;
    // liquidationStrats[1] = pancakeswapV2IbTokenLiquidationStrategy;
    // moneyMarket.setLiquidationStratsOk(liquidationStrats, true);

    // // setup fee models
    // address feeModel1 = address(new FixedFeeModel());
    // moneyMarket.setRepurchaseRewardModel(IFeeModel(feeModel1));

    // set protocol params
    // moneyMarket.setTreasury(address(0));

    _stopBroadcast();

    // write deployed addresses to json
    // NOTE: can't specify order of keys

    // money market
    _writeJson(vm.toString(address(moneyMarket)), ".moneyMarket.moneyMarketDiamond");

    // facets
    string memory facetsJson;
    facetsJson.serialize("diamondCutFacet", facetAddresses.diamondCutFacet);
    facetsJson.serialize("diamondLoupeFacet", facetAddresses.diamondLoupeFacet);
    facetsJson.serialize("viewFacet", facetAddresses.viewFacet);
    facetsJson.serialize("lendFacet", facetAddresses.lendFacet);
    facetsJson.serialize("collateralFacet", facetAddresses.collateralFacet);
    facetsJson.serialize("borrowFacet", facetAddresses.borrowFacet);
    facetsJson.serialize("nonCollatBorrowFacet", facetAddresses.nonCollatBorrowFacet);
    facetsJson.serialize("adminFacet", facetAddresses.adminFacet);
    facetsJson.serialize("liquidationFacet", facetAddresses.liquidationFacet);
    facetsJson = facetsJson.serialize("ownershipFacet", facetAddresses.ownershipFacet);
    _writeJson(facetsJson, ".moneyMarket.facets");

    // // interest rate models
    // string memory interestRateModelsJson;
    // interestRateModelsJson = interestRateModelsJson.serialize("interestRateModel1", interestRateModel1);
    // moneyMarketJson.serialize("interestRateModels", interestRateModelsJson);

    // // liquidation strategies
    // string memory liquidationStrategiesJson;
    // liquidationStrategiesJson.serialize("pancakeswapV2LiquidationStrategy", pancakeswapV2LiquidationStrategy);
    // liquidationStrategiesJson = liquidationStrategiesJson.serialize(
    //   "pancakeswapV2IbTokenLiquidationStrategy",
    //   pancakeswapV2IbTokenLiquidationStrategy
    // );
    // moneyMarketJson.serialize("liquidationStrategies", liquidationStrategiesJson);

    // // fee models
    // string memory feeModelsJson;
    // feeModelsJson = feeModelsJson.serialize("feeModel1", feeModel1);
    // moneyMarketJson = moneyMarketJson.serialize("feeModels", feeModelsJson);

    // moneyMarket = {
    //    moneyMarketDiamond: 0x...,
    //    facets: {
    //      viewFacet: 0x...,
    //    }
    // }
    // moneyMarketJson.write(configFilePath, ".moneyMarket");
  }
}
