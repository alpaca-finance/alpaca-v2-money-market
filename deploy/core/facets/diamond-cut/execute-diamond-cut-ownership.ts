import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { getConfig } from "../../../entities/config";
import { MMDiamondCutFacet__factory, MMOwnershipFacet__factory } from "../../../../typechain";
import { getDeployer } from "../../../utils/deployer-helper";
import { getOwnershipFacetSelectors } from "../../../utils/diamond";

const config = getConfig();

enum FacetCutAction {
  Add,
  Replace,
  Remove,
}

const methods = getOwnershipFacetSelectors();

const facetCuts = [
  {
    facetAddress: config.moneyMarket.facets.ownershipFacet,
    action: FacetCutAction.Add,
    functionSelectors: methods.map((each) => {
      return MMOwnershipFacet__factory.createInterface().getSighash(each);
    }),
  },
];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = await getDeployer();

  const poolDiamond = MMDiamondCutFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  await (await poolDiamond.diamondCut(facetCuts, ethers.constants.AddressZero, "0x")).wait();

  console.log(`Execute diamondCut for OwnershipFacet`);
};

export default func;
func.tags = ["ExecuteDiamondCut-Ownership"];
