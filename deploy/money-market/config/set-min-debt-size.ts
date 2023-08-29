import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";
import { IMoneyMarket__factory } from "../../../typechain";
import { ethers } from "ethers";

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

  const minDebtSize = ethers.utils.parseEther("100");

  const iMoneyMarketFactory = await IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log(`> 🟢 setMinDebtSize : ${minDebtSize.toString()}`);

  await iMoneyMarketFactory.setMinDebtSize(minDebtSize);

  console.log("✅ Done");
};

export default func;
func.tags = ["MMSetMinDebtSize"];
