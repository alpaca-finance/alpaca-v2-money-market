import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { getDeployer } from "../utils/deployer-helper";
import { MiniFL__factory } from "../../typechain";

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

  const miniFl = MiniFL__factory.connect(config.miniFL.proxy, deployer);

  console.log("----------------------");
  console.log(">>> Transfer MiniFL Ownership\n");

  console.log(`> Transfering ownership from ${deployer.address} to multisig (${multiSig}}) ...\n`);
  const tx = await miniFl.transferOwnership(multiSig);
  await tx.wait();

  console.log(`> ✅ Tx hash: ${tx.hash}\n`);
  console.log(`> ✅ Done`);
  console.log("----------------------");
};

export default func;
func.tags = ["TransferMiniFLOwnership"];
