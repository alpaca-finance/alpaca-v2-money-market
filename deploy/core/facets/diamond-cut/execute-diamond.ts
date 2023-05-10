import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

import * as readlineSync from "readline-sync";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";
import { facetContractNameToAddress, getSelectors } from "../../../utils/diamond";
import { IMMDiamondCut, MMDiamondCutFacet__factory, MMDiamondLoupeFacet__factory } from "../../../../typechain";

enum FacetCutAction {
  Add,
  Replace,
  Remove,
}

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
  */

  const FACET = "ViewFacet";
  const INITIALIZER_ADDRESS = ethers.constants.AddressZero;
  const OLD_FACET_ADDRESS = "0xA7D618BF3880f146Bbc0F0d18eB6f13F59d3D339";

  const deployer = await getDeployer();

  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();

  const diamondLoupeFacet = MMDiamondLoupeFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  const diamondCutFacet = MMDiamondCutFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log(`> Diamond cutting ${FACET}`);

  // Build the facetCuts array
  console.log(`> Build the action selectors array from ${FACET} contract`);
  const contractFactory = await ethers.getContractFactory(FACET);
  const facetAddress = facetContractNameToAddress(FACET);
  const existedFacetCuts = (await diamondLoupeFacet.facets())
    .map((each) => each.functionSelectors)
    .reduce((result, array) => result.concat(array), []);

  const previousFacet = (await diamondLoupeFacet.facets()).find((each) => each.facetAddress == OLD_FACET_ADDRESS);
  if (!previousFacet) {
    console.log("Previous facet not found");
    return;
  }

  const facetCuts: Array<IMMDiamondCut.FacetCutStruct> = [];
  const replaceSelectors: Array<string> = [];
  const addSelectors: Array<string> = [];
  const removeSelectors: Array<string> = [];
  const functionSelectors = getSelectors(contractFactory);
  // Loop through each selector to find out if it needs to replace or add
  for (const selector of functionSelectors) {
    if (existedFacetCuts.includes(selector)) {
      replaceSelectors.push(selector);
    } else {
      addSelectors.push(selector);
    }
  }
  // Loop through existed facet cuts to find out selectors to remove
  for (const selector of previousFacet.functionSelectors) {
    if (!functionSelectors.includes(selector)) {
      removeSelectors.push(selector);
    }
  }

  console.log(`> Build the facetCuts array from ${FACET} contract`);
  // Put the replaceSelectors and addSelectors into facetCuts
  if (replaceSelectors.length > 0) {
    facetCuts.push({
      facetAddress,
      action: FacetCutAction.Replace,
      functionSelectors: replaceSelectors,
    });
  }
  if (addSelectors.length > 0) {
    facetCuts.push({
      facetAddress,
      action: FacetCutAction.Add,
      functionSelectors: addSelectors,
    });
  }
  if (removeSelectors.length > 0) {
    // Get the old facet address based on the selector
    facetCuts.push({
      facetAddress: ethers.constants.AddressZero,
      action: FacetCutAction.Remove,
      functionSelectors: removeSelectors,
    });
  }

  console.log(`> Found ${replaceSelectors.length} selectors to replace`);
  console.log(`> Methods to replace:`);
  console.table(
    replaceSelectors.map((each) => {
      return {
        functionName: contractFactory.interface.getFunction(each).name,
        selector: each,
      };
    })
  );
  console.log(`> Found ${addSelectors.length} selectors to add`);
  console.log(`> Methods to add:`);
  console.table(
    addSelectors.map((each) => {
      return {
        functionName: contractFactory.interface.getFunction(each).name,
        selector: each,
      };
    })
  );
  console.log(`> Found ${removeSelectors.length} selectors to remove`);
  console.log(`> Methods to remove:`);
  console.table(
    removeSelectors.map((each) => {
      return {
        functionName: "unknown (TODO: integrate with 4bytes dictionary)",
        selector: each,
      };
    })
  );

  // Ask for confirmation
  const confirmExecuteDiamondCut = readlineSync.question("Confirm? (y/n): ");
  switch (confirmExecuteDiamondCut.toLowerCase()) {
    case "y":
      break;
    case "n":
      console.log("Aborting");
      return;
    default:
      console.log("Invalid input");
      return;
  }

  console.log("> Executing diamond cut");
  const tx = await diamondCutFacet.diamondCut(facetCuts, INITIALIZER_ADDRESS, "0x", { gasLimit: 10000000 });
  console.log(`> Tx is submitted: ${tx.hash}`);
  console.log(`> Waiting for tx to be mined`);
  await tx.wait();
  console.log(`> Tx is mined`);
};

export default func;
func.tags = ["ExecuteDiamondCut"];
