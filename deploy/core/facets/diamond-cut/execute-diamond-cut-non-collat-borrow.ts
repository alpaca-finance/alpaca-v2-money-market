import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { getConfig } from "../../../entities/config";
import { MMDiamondCutFacet__factory, NonCollatBorrowFacet__factory } from "../../../../typechain";
import { getDeployer } from "../../../utils/deployer-helper";
import { getNonCollatBorrowFacetSelectors } from "../../../utils/diamond";

const config = getConfig();

enum FacetCutAction {
  Add,
  Replace,
  Remove,
}

const methods = getNonCollatBorrowFacetSelectors();

const facetCuts = [
  {
    facetAddress: config.moneyMarket.facets.nonCollatBorrowFacet,
    action: FacetCutAction.Add,
    functionSelectors: methods.map((each) => {
      return NonCollatBorrowFacet__factory.createInterface().getSighash(each);
    }),
  },
];

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = await getDeployer();

  const poolDiamond = MMDiamondCutFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  const tx = await poolDiamond.diamondCut(facetCuts, ethers.constants.AddressZero, "0x");

  console.log(`> Tx is submitted: ${tx.hash}`);
  console.log(`> Waiting for tx to be mined`);

  await tx.wait();

  console.log(`> Tx is mined`);
  console.log(`Execute diamondCut for NonCollatBorrowFacet`);
};

export default func;
func.tags = ["ExecuteDiamondCut-NonCollatBorrow"];
