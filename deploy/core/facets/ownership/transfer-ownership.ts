import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";
import { AdminFacet__factory, MMOwnershipFacet__factory } from "../../../../typechain";

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

  const configFileHelper = new ConfigFileHelper();

  const config = configFileHelper.getConfig();
  const deployer = await getDeployer();
  const multiSig = config.opMultiSig;

  const adminFacet = AdminFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);
  const ownershipFacet = MMOwnershipFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  console.log("----------------------");
  console.log(">>> Transfer Money Market Ownership\n");

  console.log(`> Removing ${deployer.address} from operatorsOk...`);
  const operatorRemoved = await adminFacet.setOperatorsOk([deployer.address], false);
  await operatorRemoved.wait();
  console.log(`> ✅ Tx hash: ${operatorRemoved.hash}\n`);

  console.log(`> Removing ${deployer.address} from riskManagersOk...`);
  const riskManagerRemoved = await adminFacet.setRiskManagersOk([deployer.address], false);
  await riskManagerRemoved.wait();
  console.log(`> ✅ Tx hash: ${riskManagerRemoved.hash}\n`);

  console.log(`> Adding ${multiSig} to operatorsOk...`);
  const operatorAdded = await adminFacet.setRiskManagersOk([multiSig], true);
  await operatorAdded.wait();
  console.log(`> ✅ Tx hash: ${operatorAdded.hash}\n`);

  console.log(`> Adding ${multiSig} to riskManagersOk...`);
  const riskManagerAdded = await adminFacet.setOperatorsOk([multiSig], true);
  await riskManagerAdded.wait();
  console.log(`> ✅ Tx hash: ${riskManagerAdded.hash}\n`);

  console.log(`> Transfering ownership from ${deployer.address} to multisig (${multiSig}}) ...`);
  const transferOwnership = await ownershipFacet.transferOwnership(multiSig);
  await transferOwnership.wait();
  console.log(`> ✅ Tx hash: ${transferOwnership.hash}`);
  console.log(`> ✅ Done`);

  console.log("\n[Please accept the ownership transfer transaction on multisig wallet]");
  console.log("----------------------");
};

export default func;
func.tags = ["TransferMoneyMarketOwnership"];
