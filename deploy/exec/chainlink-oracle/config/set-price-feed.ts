import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IChainLinkPriceOracle__factory } from "../../../../typechain";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
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

  const TOKEN0S: string[] = [config.tokens.wbeth];
  const TOKEN1S: string[] = [config.usdPlaceholder];
  const SOURCES: string[] = ["0x97398272a927c56735f7bfce95752540f5e23ccd"];

  const deployer = await getDeployer();
  const chainLinkOracle = IChainLinkPriceOracle__factory.connect(config.oracle.chainlinkOracle, deployer);

  const setPriceFeedTx = await chainLinkOracle.setPriceFeeds(TOKEN0S, TOKEN1S, SOURCES);
  console.log(`✅Done at tx: ${setPriceFeedTx.hash}`);
};

export default func;
func.tags = ["SetPriceFeed"];
