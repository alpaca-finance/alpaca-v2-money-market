import { BigNumber } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IMoneyMarket__factory } from "../../../../typechain";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

type SetTokenMaxCapacityInput = {
  token: string;
  newMaxCollateral?: BigNumber;
  newMaxBorrow?: BigNumber;
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();
  const deployer = await getDeployer();
  const moneyMarket = IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);
  /*
      ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
      ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
      ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
      ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
      ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
      ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
      Check all variables below before execute the deployment script
  */

  const TOKEN_MAX_CAP_INPUTS: SetTokenMaxCapacityInput[] = [
    {
      token: config.tokens.busd,
      newMaxBorrow: BigNumber.from(0),
    },
  ];

  const infos = await Promise.all(
    TOKEN_MAX_CAP_INPUTS.map(async (input) => {
      const TOKEN_CONFIG = await moneyMarket.getTokenConfig(input.token);

      return {
        TOKEN: input.token,
        NEW_MAX_COLLARERAL: input.newMaxCollateral || TOKEN_CONFIG.maxCollateral,
        NEW_MAX_BORROW: input.newMaxBorrow || TOKEN_CONFIG.maxBorrow,
      };
    })
  );

  for (const info of infos) {
    const setTokenMaxCapTx = await moneyMarket.setTokenMaximumCapacities(
      info.TOKEN,
      info.NEW_MAX_COLLARERAL,
      info.NEW_MAX_BORROW
    );

    const setTokenMaxCapReceipt = await setTokenMaxCapTx.wait();

    console.log(`✅ Done SetMaxCapacity for ${info.TOKEN} at TX: ${setTokenMaxCapReceipt.transactionHash}`);
  }
};

export default func;
func.tags = ["SetTokenMaxCapacity"];
