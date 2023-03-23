// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "solidity/tests/utils/StdJson.sol";
import "../../../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { TripleSlopeModel7 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel7.sol";
import { PancakeswapV2LiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2LiquidationStrategy.sol";
import { PancakeswapV2IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";
import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";
import { LibMoneyMarketDeployment } from "script/deployments/libraries/LibMoneyMarketDeployment.sol";

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

    _stopBroadcast();

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
  }
}
