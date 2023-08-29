import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const deployer = await getDeployer();

  const FixedFeeModel500BpsFactory = await ethers.getContractFactory("FixedFeeModel500Bps", deployer);

  const fixedFeeModel500Bps = await FixedFeeModel500BpsFactory.deploy();

  console.log(`> 🟢 FixedFeeModel500Bps Address: ${fixedFeeModel500Bps.address}`);

  configFileHelper.setFixedFeeModel500Bps(fixedFeeModel500Bps.address);
};

export default func;
func.tags = ["MMSetFixedFeeModel500BpsDeploy"];
