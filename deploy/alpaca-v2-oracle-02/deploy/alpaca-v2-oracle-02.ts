import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = await getDeployer();
  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();

  /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
  */

  const oracle = config.oracle.oracleMedianizer;
  const usd = config.usdPlaceholder;

  console.log(`> oracle : ${oracle}`);
  console.log(`> usd : ${usd}`);
  const AlpacaV2Oracle02Factory = await ethers.getContractFactory("AlpacaV2Oracle02", deployer);

  const alpacaV2Oracle02 = await AlpacaV2Oracle02Factory.deploy(oracle, usd);

  console.log(`> 🟢 alpacaV2Oracle02 Address: ${alpacaV2Oracle02.address}`);
  configFileHelper.setAlpacaV2Oracle02(alpacaV2Oracle02.address);
};

export default func;
func.tags = ["MMAlpacaV2Oracle02Deploy"];
