import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const config = new ConfigFileHelper();
  const deployer = await getDeployer();
  const LendFacet = await ethers.getContractFactory("LendFacet", deployer);

  console.log(`Deploying LendFacet Contract`);
  const lendFacet = await LendFacet.deploy();
  await lendFacet.deployed();
  console.log(`Deployed at: ${lendFacet.address}`);

  config.setLendFacets(lendFacet.address);
};

export default func;
func.tags = ["LendFacetDeploy"];
