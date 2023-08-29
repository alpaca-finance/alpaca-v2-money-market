import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { getDeployer } from "../utils/deployer-helper";
import { OwnableUpgradeable__factory } from "../../typechain/factories/@openzeppelin/contracts-upgradeable/access/index";

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

  const contractToTransfers = [
    config.moneyMarket.moneyMarketDiamond,
    config.oracle.alpacaV2Oracle02,
    config.oracle.chainlinkOracle,
    config.oracle.oracleMedianizer,
    config.miniFL.proxy,
    config.rewarders[0].address,
    config.rewarders[1].address,
  ];

  const deployer = await getDeployer();
  const opMultiSig = config.opMultiSig;

  for (const contractAddress of contractToTransfers) {
    console.log(`>>> 🔧 Transfer ownership of ${contractAddress} to: ${opMultiSig}`);
    const contract = OwnableUpgradeable__factory.connect(contractAddress, deployer);
    const transferOwnershipTx = await contract.transferOwnership(opMultiSig);
    await transferOwnershipTx.wait();
    console.log(`> 🟢 Done | Tx hash: ${transferOwnershipTx.hash}\n`);
  }

  console.log("\n✅ All Done");
};

export default func;
func.tags = ["TransferOwnership"];
