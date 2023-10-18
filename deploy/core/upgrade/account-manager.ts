import { ethers, upgrades } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";
import { TimelockTransaction } from "../../interfaces";
import { getDeployer } from "../../utils/deployer-helper";
import { getProxyAdminFactory } from "@openzeppelin/hardhat-upgrades/dist/utils";
import { TimelockService, fileService } from "../../services";
import { compare } from "../../utils/address";

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

  /*
   * Since Money Market contract is not deployed via hardhat-deploy, we need to `forceImport` Openzeppelin's unknowJson
   * ref: https://docs.openzeppelin.com/upgrades-plugins/1.x/api-hardhat-upgrades#force-import
   */

  const TITLE = "upgrade_money_market_account_manager";
  const MONEY_MARKET_ACCOUNT_MANAGER = "MoneyMarketAccountManager";
  const EXACT_ETA = "1697713200";

  const config = new ConfigFileHelper().getConfig();
  const timelockTransactions: Array<TimelockTransaction> = [];
  const deployer = await getDeployer();
  const chainId = await deployer.getChainId();
  const accountManager = config.moneyMarket.accountManager;

  const proxyAdminFactory = await getProxyAdminFactory(hre, deployer);
  const proxyAdmin = proxyAdminFactory.attach(config.proxyAdmin);
  const proxyAdminOwner = await proxyAdmin.owner();

  let nonce = await deployer.getTransactionCount();

  if (compare(proxyAdminOwner, config.timelock)) {
    console.log("------------------");
    console.log(`> Upgrading ${MONEY_MARKET_ACCOUNT_MANAGER} through Timelock + ProxyAdmin`);
    console.log("> Prepare upgrade & deploy if needed a new IMPL automatically.");
    const newAccountManager = await ethers.getContractFactory(MONEY_MARKET_ACCOUNT_MANAGER);
    const preparedAccountManager = await upgrades.prepareUpgrade(accountManager.proxy, newAccountManager, {
      unsafeAllow: ["constructor", "delegatecall"],
    });
    console.log(`> Implementation address: ${preparedAccountManager}`);
    console.log("✅ Done");

    timelockTransactions.push(
      await TimelockService.queueTransaction(
        chainId,
        `> Queue tx to upgrade ${MONEY_MARKET_ACCOUNT_MANAGER}`,
        config.proxyAdmin,
        "0",
        "upgrade(address,address)",
        ["address", "address"],
        [accountManager.proxy, preparedAccountManager],
        EXACT_ETA,
        { nonce: nonce++ }
      )
    );
  } else {
    console.log("------------------");
    console.log(`> Upgrading ${MONEY_MARKET_ACCOUNT_MANAGER} through ProxyAdmin`);
    console.log("> Upgrade & deploy if needed a new IMPL automatically.");
    const newAccountManager = await ethers.getContractFactory(MONEY_MARKET_ACCOUNT_MANAGER);
    const preparedAccountManager = await upgrades.prepareUpgrade(accountManager.proxy, newAccountManager, {
      unsafeAllow: ["constructor", "delegatecall"],
    });
    console.log(`> Implementation address: ${preparedAccountManager}`);

    // Perform actual upgrade
    await upgrades.upgradeProxy(accountManager.proxy, newAccountManager);
    console.log("✅ Done");
  }

  if (timelockTransactions.length > 0) {
    const timestamp = Math.floor(new Date().getTime() / 1000);
    fileService.writeJson(`${timestamp}_${TITLE}`, timelockTransactions);
  }
};

export default func;
func.tags = ["UpgradeMoneyMarketAccountManager"];
