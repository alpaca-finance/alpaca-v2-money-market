import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const SLOPE_MODEL = "MMFlatSlopeModel3";

  const deployer = await getDeployer();
  const InterestModel = await ethers.getContractFactory(SLOPE_MODEL, deployer);

  console.log(`Deploying Interest Model Contract`);
  const model = await InterestModel.deploy();
  await model.deployed();
  console.log(`Deployed at: ${model.address}`);
};

export default func;
func.tags = ["FlatSlopeModelDeploy"];
