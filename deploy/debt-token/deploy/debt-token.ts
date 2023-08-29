import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const deployer = await getDeployer();

  const DebtTokenFactory = await ethers.getContractFactory("DebtToken", deployer);

  const debtToken = await DebtTokenFactory.deploy();

  console.log(`> 🟢 debtToken Address: ${debtToken.address}`);

  configFileHelper.setDebtToken(debtToken.address);
};

export default func;
func.tags = ["MMDebtTokenDeploy"];
