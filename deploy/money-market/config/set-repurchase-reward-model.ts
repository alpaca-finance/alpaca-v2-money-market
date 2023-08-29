import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";
import { IMoneyMarket__factory } from "../../../typechain";

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

  const fixFeeModel500Bps = config.sharedConfig.fixFeeModel500Bps;

  const iMoneyMarketFactory = await IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log(`> 🟢 setRepurchaseRewardModel : ${fixFeeModel500Bps}`);

  await iMoneyMarketFactory.setRepurchaseRewardModel(fixFeeModel500Bps);

  console.log("✅ Done");
};

export default func;
func.tags = ["MMSetRepurchaseRewardModel"];
