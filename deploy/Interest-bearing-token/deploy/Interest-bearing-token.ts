import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const deployer = await getDeployer();

  const InterestBearingTokenFactory = await ethers.getContractFactory("InterestBearingToken", deployer);

  const interestBearingToken = await InterestBearingTokenFactory.deploy();

  console.log(`> 🟢 InterestBearingToken Address: ${interestBearingToken.address}`);

  configFileHelper.setInterestBearingToken(interestBearingToken.address);
};

export default func;
func.tags = ["MMInterestBearingTokenDeploy"];
