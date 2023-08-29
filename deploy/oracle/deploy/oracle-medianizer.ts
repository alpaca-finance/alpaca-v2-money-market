import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers, upgrades } from "hardhat";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const deployer = await getDeployer();

  console.log(">> Deploying an upgradable OracleMedianizer contract");

  const OracleMedianizer = await ethers.getContractFactory("OracleMedianizer", deployer);
  const oracleMedianizer = await upgrades.deployProxy(OracleMedianizer, {
    unsafeAllow: ["delegatecall"],
  });
  await oracleMedianizer._deployed();

  console.log(`>> 🟢 Deployed OracleMedianizer : at ${oracleMedianizer.address}`);

  configFileHelper.setOracleMedianizer(oracleMedianizer.address);
};

export default func;
func.tags = ["OracleMedianizerDeploy"];
