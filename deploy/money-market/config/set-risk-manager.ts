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

  const isOk = true;
  const riskManagers = ["0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51"];

  const iMoneyMarketFactory = await IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log(`> 🟢 setRiskManagersOk : ${riskManagers} , ${isOk}`);

  await iMoneyMarketFactory.setRiskManagersOk(riskManagers, isOk);

  console.log("✅ Done");
};

export default func;
func.tags = ["MMSetRiskManagersOk"];
