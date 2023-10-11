import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../../utils/deployer-helper";
import { ERC20__factory, IMoneyMarket__factory } from "../../../../typechain";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { AssetTier } from "../../../interfaces";
import { parseUnits } from "ethers/lib/utils";
import { BigNumber } from "ethers";

type OpenMarketInput = {
  token: string;
  interestModel: string;
  tier: number;
  collateralFactor: number;
  borrowingFactor: number;
  maxCollateral: number;
  maxBorrow: number;
};

type TokenConfigInput = {
  tier: number;
  collateralFactor: number;
  borrowingFactor: number;
  maxBorrow: BigNumber;
  maxCollateral: BigNumber;
};

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

  const inputs: OpenMarketInput[] = [
    {
      token: config.tokens.wbeth,
      interestModel: config.sharedConfig.doubleSlope2,
      tier: AssetTier.COLLATERAL,
      collateralFactor: 8500,
      borrowingFactor: 9000,
      maxCollateral: 50_000,
      maxBorrow: 45_000,
    },
  ];

  const deployer = await getDeployer();

  const moneyMarket = IMoneyMarket__factory.connect(config.moneyMarket.moneyMarketDiamond, deployer);

  for (const input of inputs) {
    const token = ERC20__factory.connect(input.token, deployer);
    const tokenDecimal = await token.decimals();

    const maxBorrow = parseUnits(input.maxBorrow.toString(), tokenDecimal);
    const maxCollateral = parseUnits(input.maxCollateral.toString(), tokenDecimal);

    const underlyingTokenConfigInput: TokenConfigInput = {
      tier: input.tier,
      collateralFactor: 0,
      borrowingFactor: input.borrowingFactor,
      maxBorrow: maxBorrow,
      maxCollateral: BigNumber.from(0),
    };

    const ibTokenConfigInput: TokenConfigInput = {
      tier: input.tier,
      collateralFactor: input.collateralFactor,
      borrowingFactor: 1, // 1 for preventing divided by zero
      maxBorrow: BigNumber.from(0),
      maxCollateral: maxCollateral,
    };

    console.log(`Opening Market: ${input.token}`);
    const openMarketTx = await moneyMarket.openMarket(input.token, underlyingTokenConfigInput, ibTokenConfigInput);
    await openMarketTx.wait();
    console.log(`✅Done:${openMarketTx.hash}`);

    console.log(`Setting interestModel: ${input.token}`);
    const setInterestModelTx = await moneyMarket.setInterestModel(input.token, input.interestModel);
    await setInterestModelTx.wait();
    console.log(`✅Done:${setInterestModelTx.hash}`);
  }
};

export default func;
func.tags = ["OpenMarket"];
