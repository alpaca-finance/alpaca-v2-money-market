import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { GnosisSafeMultiSigService } from "../services/multisig/gnosis-safe";
import { ethers } from "hardhat";
import { getDeployer } from "../utils/deployer-helper";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { MMOwnershipFacet__factory } from "../../typechain";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();

  const config = configFileHelper.getConfig();
  const deployer = await getDeployer();
  const chainId = await deployer.getChainId();

  /*
    ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
    ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
    ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
    ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
    ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
    ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
    Check all variables below before execute the deployment script
  */

  const ownershipFacet = MMOwnershipFacet__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  const deployerWallet = new ethers.Wallet(process.env.DEPLOYER_PRIVATE_KEY as string, deployer.provider);

  const multiSig = new GnosisSafeMultiSigService(chainId, config.opMultiSig, deployerWallet);
  const txHash = await multiSig.proposeTransaction(
    ownershipFacet.address,
    "0",
    ownershipFacet.interface.encodeFunctionData("acceptOwnership")
  );

  console.log(`> 🟢 Transaction Proposed`);
  console.log(`> ✅ Tx hash: ${txHash}`);
};

export default func;
func.tags = ["AcceptMoneyMarketOwnership"];
