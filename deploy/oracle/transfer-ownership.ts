import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Ownable__factory } from "../../typechain/factories/solidity/contracts/upgradable/ProxyAdmin.sol";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { getDeployer } from "../utils/deployer-helper";
import { OwnableUpgradeable__factory } from "../../typechain";

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

  const alpacaV2Oracle = Ownable__factory.connect(config.oracle.alpacaV2Oracle, deployer);
  const alpacaV2Oracle02 = Ownable__factory.connect(config.oracle.alpacaV2Oracle02, deployer);
  const chainlinkOracle = Ownable__factory.connect(config.oracle.chainlinkOracle, deployer);
  const oracleMedianizer = Ownable__factory.connect(config.oracle.oracleMedianizer, deployer);

  console.log("----------------------");
  console.log(">>> Transfer Oracles Ownership\n");

  console.log(await alpacaV2Oracle.owner());
  console.log(await alpacaV2Oracle02.owner());
  console.log(await chainlinkOracle.owner());
  console.log(await oracleMedianizer.owner());

  console.log(`> Transfering ownership from ${deployer.address} to multisig (${multiSig}}) ...\n`);

  console.log("> alpacaV2Oracle");
  const v2OracleTx = await alpacaV2Oracle.transferOwnership(multiSig);
  await v2OracleTx.wait();
  console.log(`> ✅ Tx hash: ${v2OracleTx.hash}\n`);

  console.log("> alpacaV2Oracle02");
  const v2Oracle02Tx = await alpacaV2Oracle02.transferOwnership(multiSig);
  await v2Oracle02Tx.wait();
  console.log(`> ✅ Tx hash: ${v2Oracle02Tx.hash}\n`);

  console.log("> chainlinkOracle");
  const chainlinkOracleTx = await chainlinkOracle.transferOwnership(multiSig);
  await chainlinkOracleTx.wait();
  console.log(`> ✅ Tx hash: ${chainlinkOracleTx.hash}\n`);

  console.log("> oracleMedianizer");
  const oracleMedianizerTx = await oracleMedianizer.transferOwnership(multiSig);
  await oracleMedianizerTx.wait();
  console.log(`> ✅ Tx hash: ${oracleMedianizerTx.hash}\n`);

  console.log(`\n> ✅ Done`);
  console.log("----------------------");
};

export default func;
func.tags = ["TransferOraclesOwnership"];
