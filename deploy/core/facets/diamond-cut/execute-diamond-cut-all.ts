import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { getConfig } from "../../../entities/config";
import {
  AdminFacet__factory,
  BorrowFacet__factory,
  CollateralFacet__factory,
  FlashloanFacet__factory,
  LendFacet__factory,
  LiquidationFacet__factory,
  MMDiamondCutFacet__factory,
  MMDiamondLoupeFacet__factory,
  MMOwnershipFacet__factory,
  NonCollatBorrowFacet__factory,
  ViewFacet__factory,
} from "../../../../typechain";
import { getDeployer } from "../../../utils/deployer-helper";
import {
  getAdminFacetSelectors,
  getBorrowFacetSelectors,
  getCollateralFacetSelectors,
  getFlashloanFacetSelectors,
  getLendFacetSelectors,
  getLiquidationFacetSelectors,
  getMMDiamondLoupeFacetSelectors,
  getNonCollatBorrowFacetSelectors,
  getOwnershipFacetSelectors,
  getViewFacetSelectors,
} from "../../../utils/diamond";
import { ContractFactory } from "ethers";

const config = getConfig();

enum FacetCutAction {
  Add,
  Replace,
  Remove,
}

interface FacetCutInputConfig {
  methods: string[];
  address: string;
  name: string;
  factory: ContractFactory;
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = await getDeployer();

  const poolDiamond = MMDiamondCutFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  const facetCutInputConfigs = getFacetCutInputConfig();

  for (const config of facetCutInputConfigs) {
    console.log(`> Diamond cutting ${config.name}`);

    const facetCuts = await Promise.all([
      {
        facetAddress: config.address,
        action: FacetCutAction.Add,
        functionSelectors: await Promise.all(
          config.methods.map(async (each) => {
            return await config.factory.interface.getSighash(each);
          })
        ),
      },
    ]);

    const tx = await poolDiamond.diamondCut(facetCuts, ethers.constants.AddressZero, "0x", { gasLimit: 10000000 });

    console.log(`> Tx is submitted: ${tx.hash}`);
    console.log(`> Waiting for tx to be mined`);

    await tx.wait();

    console.log(`> Tx is mined`);
    console.log(`> 🟢 Execute diamondCut for ${config.name}`);
  }
};

function getFacetCutInputConfig(): FacetCutInputConfig[] {
  return [
    {
      methods: getMMDiamondLoupeFacetSelectors(),
      address: config.moneyMarket.facets.diamondLoupeFacet,
      name: "DiamondLoupeFacet",
      factory: new MMDiamondLoupeFacet__factory(),
    },
    {
      methods: getViewFacetSelectors(),
      address: config.moneyMarket.facets.viewFacet,
      name: "ViewFacet",
      factory: new ViewFacet__factory(),
    },
    {
      methods: getLendFacetSelectors(),
      address: config.moneyMarket.facets.lendFacet,
      name: "LendFacet",
      factory: new LendFacet__factory(),
    },
    {
      methods: getCollateralFacetSelectors(),
      address: config.moneyMarket.facets.collateralFacet,
      name: "CollateralFacet",
      factory: new CollateralFacet__factory(),
    },
    {
      methods: getBorrowFacetSelectors(),
      address: config.moneyMarket.facets.borrowFacet,
      name: "BorrowFacet",
      factory: new BorrowFacet__factory(),
    },
    {
      methods: getNonCollatBorrowFacetSelectors(),
      address: config.moneyMarket.facets.nonCollatBorrowFacet,
      name: "NonCollatBorrowFacet",
      factory: new NonCollatBorrowFacet__factory(),
    },
    {
      methods: getAdminFacetSelectors(),
      address: config.moneyMarket.facets.adminFacet,
      name: "AdminFacet",
      factory: new AdminFacet__factory(),
    },
    {
      methods: getLiquidationFacetSelectors(),
      address: config.moneyMarket.facets.liquidationFacet,
      name: "LiquidationFacet",
      factory: new LiquidationFacet__factory(),
    },
    {
      methods: getOwnershipFacetSelectors(),
      address: config.moneyMarket.facets.ownershipFacet,
      name: "OwnershipFacet",
      factory: new MMOwnershipFacet__factory(),
    },
    {
      methods: getFlashloanFacetSelectors(),
      address: config.moneyMarket.facets.flashloanFacet,
      name: "FlashloanFacet",
      factory: new FlashloanFacet__factory(),
    },
  ];
}

export default func;
func.tags = ["ExecuteDiamondCut-All"];
