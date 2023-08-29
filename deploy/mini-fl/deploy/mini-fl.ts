import { ethers, upgrades } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { getImplementationAddress } from "@openzeppelin/upgrades-core";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
  */

  const ALPACA = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";
  const maxAlpacaPerSecond = ethers.utils.parseEther("1");

  const configFileHelper = new ConfigFileHelper();
  const deployer = await getDeployer();

  const MiniFLFactory = await ethers.getContractFactory("MiniFL", deployer);

  const miniFL = await upgrades.deployProxy(MiniFLFactory, [ALPACA, maxAlpacaPerSecond], {
    unsafeAllow: ["delegatecall"],
  });
  const implAddress = await getImplementationAddress(ethers.provider, miniFL.address);

  console.log(`> 🟢 MiniFL implementation deployed at: ${implAddress}`);
  console.log(`> 🟢 MiniFL proxy deployed at: ${miniFL.address}`);

  configFileHelper.setMiniFLPoolDeploy(miniFL.address, implAddress);
};

export default func;
func.tags = ["MiniFLDeploy"];
