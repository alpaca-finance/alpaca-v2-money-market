import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { getDeployer } from "../utils/deployer-helper";
import { IMoneyMarket__factory } from "../../typechain";

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

  const INPUTS = [
    {
      account: "0xD0dfE9277B1DB02187557eAeD7e25F74eF2DE8f3",
      token: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
      model: "0xB0f78514edd28E2e1617a7479CCf7F0855aF979a",
    },
  ];

  const deployer = await getDeployer();
  let nonce = await deployer.getTransactionCount();

  for (const input of INPUTS) {
    console.log(`>>> 🔧 Setting Interest Model ${input.model} for: ${input.token}`);
    const moneyMarket = IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);
    const tx = await moneyMarket.setNonCollatInterestModel(input.account, input.token, input.model, { nonce: nonce++ });
    await tx.wait();
    console.log(`> 🟢 Done | Tx hash: ${tx.hash}\n`);
  }

  console.log("\n✅ All Done");
};

export default func;
func.tags = ["SetNonCollatInterestModel"];
