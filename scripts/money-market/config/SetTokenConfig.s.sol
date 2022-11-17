// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console } from "solidity/tests/utils/Script.sol";
// core
import { MoneyMarketDiamond } from "../../../solidity/contracts/money-market/MoneyMarketDiamond.sol";

// facets
import { DiamondCutFacet, IDiamondCut } from "../../../solidity/contracts/money-market/facets/DiamondCutFacet.sol";
import { DiamondLoupeFacet } from "../../../solidity/contracts/money-market/facets/DiamondLoupeFacet.sol";
import { LendFacet, ILendFacet } from "../../../solidity/contracts/money-market/facets/LendFacet.sol";
import { CollateralFacet, ICollateralFacet } from "../../../solidity/contracts/money-market/facets/CollateralFacet.sol";
import { BorrowFacet, IBorrowFacet } from "../../../solidity/contracts/money-market/facets/BorrowFacet.sol";
import { NonCollatBorrowFacet, INonCollatBorrowFacet } from "../../../solidity/contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { AdminFacet, IAdminFacet } from "../../../solidity/contracts/money-market/facets/AdminFacet.sol";
import { RepurchaseFacet, IRepurchaseFacet } from "../../../solidity/contracts/money-market/facets/RepurchaseFacet.sol";

// libs
import { LibMoneyMarket01 } from "../../../solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";

// initializers
import { DiamondInit } from "../../../solidity/contracts/money-market/initializers/DiamondInit.sol";

contract SetTokenConfig is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address alpacaDeployer = address(0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51);
    address deployer = vm.addr(deployerPrivateKey);

    if (alpacaDeployer == deployer) {
      vm.startBroadcast(deployer);
    } else {
      vm.startBroadcast();
    }

    // change value here
    AdminFacet adminFacet = AdminFacet(0x9BfAb04dD186C058DE6B04083A17181b1f4604Cd);

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](4);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 10000e18,
      maxCollateral: 30000e18,
      maxToleranceExpiredSecond: 604800
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(0x55d398326f99059fF775485246999027B3197955),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 10000e18,
      maxCollateral: 30000e18,
      maxToleranceExpiredSecond: 604800
    });

    _inputs[2] = IAdminFacet.TokenConfigInput({
      token: address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 10000e18,
      maxCollateral: 30000e18,
      maxToleranceExpiredSecond: 604800
    });

    adminFacet.setTokenConfigs(_inputs);
    vm.stopBroadcast();
  }
}
