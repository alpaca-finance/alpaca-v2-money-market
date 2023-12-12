import { BigNumber } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { IMoneyMarket__factory } from "../../../../typechain";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

type SetTokenConfigInput = {
  token: string;
  tier?: BigNumber;
  collateralFactor?: string;
  borrowingFactor?: string;
  maxCollateral?: BigNumber;
  maxBorrow?: BigNumber;
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

  const TOKEN_CONFIG_INPUTS: SetTokenConfigInput[] = [
    // BUSD
    {
      token: "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
      borrowingFactor: "5000",
    },
    // ibBUSD
    {
      token: "0x3f38BA29AcC107E6F0b059a17c9bAb0598d0f249",
      collateralFactor: "4000",
    },
  ];

  const tokens = TOKEN_CONFIG_INPUTS.map((config) => config.token);
  const infos = await Promise.all(
    TOKEN_CONFIG_INPUTS.map(async (input) => {
      const TOKEN_CONFIG = await moneyMarket.getTokenConfig(input.token);

      return {
        tier: input.tier || TOKEN_CONFIG.tier,
        collateralFactor: input.collateralFactor || TOKEN_CONFIG.collateralFactor,
        borrowingFactor: input.borrowingFactor || TOKEN_CONFIG.borrowingFactor,
        maxCollateral: input.maxCollateral || TOKEN_CONFIG.maxCollateral,
        maxBorrow: input.maxBorrow || TOKEN_CONFIG.maxBorrow,
      };
    })
  );

  const setTokenConfigTx = await moneyMarket.setTokenConfigs(tokens, infos);

  const setTokenConfigReceipt = await setTokenConfigTx.wait();

  console.log(`✅ Done TokenConfig done at TX: ${setTokenConfigReceipt.transactionHash}`);
};

export default func;
func.tags = ["SetTokenConfig"];
