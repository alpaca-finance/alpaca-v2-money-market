import { ethers, upgrades } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();
  const deployer = await getDeployer();
  /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
  */

  const moneyMarket = config.moneyMarket.moneyMarketDiamond;
  const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const nativeRelayer = config.nativeRelayer;

  const MoneyMarketAccountManagerFactory = await ethers.getContractFactory("MoneyMarketAccountManager", deployer);

  const moneyMarketAccountManager = await upgrades.deployProxy(
    MoneyMarketAccountManagerFactory,
    [moneyMarket, weth, nativeRelayer],
    {
      unsafeAllow: ["delegatecall"],
    }
  );
  const implAddress = await getImplementationAddress(ethers.provider, moneyMarketAccountManager.address);

  console.log(`> 🟢 MoneyMarketAccountManager implementation deployed at: ${implAddress}`);
  console.log(`> 🟢 MoneyMarketAccountManager proxy deployed at: ${moneyMarketAccountManager.address}`);

  configFileHelper.setMoneyMarketAccountManagerDeploy(moneyMarketAccountManager.address, implAddress);
};

export default func;
func.tags = ["MoneyMarketAccountManagerDeploy"];
