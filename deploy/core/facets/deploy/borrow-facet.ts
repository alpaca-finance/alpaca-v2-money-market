import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const config = new ConfigFileHelper();
  const deployer = await getDeployer();
  const BorrowFacet = await ethers.getContractFactory("BorrowFacet", deployer);

  console.log(`Deploying BorrowFacet Contract`);
  const borrowFacet = await BorrowFacet.deploy();
  await borrowFacet.deployed();
  console.log(`Deployed at: ${borrowFacet.address}`);

  config.setBorrowFacet(borrowFacet.address);
};

export default func;
func.tags = ["BorrowFacetDeploy"];
