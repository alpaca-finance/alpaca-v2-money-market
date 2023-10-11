import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { OracleMedianizer__factory } from "../../../../typechain";
import { ConfigFileHelper } from "../../../file-helper.ts/config-file.helper";
import { getDeployer } from "../../../utils/deployer-helper";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();
  const DEFAULT_MAX_PRICE_DEVIATION = "1000000000000000000";
  const DEFAULT_MAX_PRICE_STALE = 86400;
  /*
      ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
      ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
      ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
      ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
      ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
      ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
      Check all variables below before execute the deployment script
  */

  const TOKEN0S: string[] = [config.tokens.wbeth];
  const TOKEN1S: string[] = [config.usdPlaceholder];
  const MAX_PRICE_DEVIATIONS: string[] = [DEFAULT_MAX_PRICE_DEVIATION];
  const MAX_PRICE_STALES: number[] = [DEFAULT_MAX_PRICE_STALE];
  const SOURCES = [[config.oracle.chainlinkOracle]];

  const deployer = await getDeployer();
  const oracleMedianizer = OracleMedianizer__factory.connect(config.oracle.oracleMedianizer, deployer);

  const setMultiplePrimarySourcesTx = await oracleMedianizer.setMultiPrimarySources(
    TOKEN0S,
    TOKEN1S,
    MAX_PRICE_DEVIATIONS,
    MAX_PRICE_STALES,
    SOURCES
  );
  console.log(`✅Done: ${setMultiplePrimarySourcesTx.hash}`);
};

export default func;
func.tags = ["SetMultiplePrimarySources"];
