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

  const newMaxLiquidateBps = 5000;
  const newLiquidationThreshold = 11000;

  const iMoneyMarketFactory = await IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log(`> 🟢 setLiquidationParams : ${newMaxLiquidateBps} , ${newLiquidationThreshold}`);

  const tx = await iMoneyMarketFactory.setLiquidationParams(newMaxLiquidateBps, newLiquidationThreshold);

  console.log(`> Tx is submitted: ${tx.hash}`);
  console.log(`> Waiting for tx to be mined`);

  await tx.wait();

  console.log(`> Tx is mined`);
  console.log("✅ Done");
};

export default func;
func.tags = ["MMSetLiquidationParams"];
