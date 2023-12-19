import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const config = new ConfigFileHelper();
  const deployer = await getDeployer();
  const LiquidationFacet = await ethers.getContractFactory("LiquidationFacet", deployer);

  console.log(`Deploying LiquidationFacet Contract`);
  const liquidationFacet = await LiquidationFacet.deploy();
  await liquidationFacet.deployed();
  console.log(`Deployed at: ${liquidationFacet.address}`);

  config.setLiquidationFacet(liquidationFacet.address);
};

export default func;
func.tags = ["LiquidationFacetDeploy"];
