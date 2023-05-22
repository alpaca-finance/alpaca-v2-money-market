import { ethers } from "ethers";
import { network } from "hardhat";
import { HttpNetworkConfig } from "hardhat/types";
import { CallOverrides } from "@ethersproject/contracts";
import { ITimelock__factory } from "../../typechain";
import { GnosisSafeMultiSigService } from "./multisig/gnosis-safe";
import { TimelockTransaction } from "../interfaces";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";
import { getDeployer } from "../utils/deployer-helper";
import { compare } from "../utils/address";

export async function queueTransaction(
  chainId: number,
  info: string,
  target: string,
  value: string,
  signature: string,
  paramTypes: Array<string>,
  params: Array<any>,
  eta: string,
  overrides?: CallOverrides
): Promise<TimelockTransaction> {
  const deployer = await getDeployer();
  console.log(`------------------`);
  console.log(`>> Queue tx for: ${info}`);
  const config = new ConfigFileHelper().getConfig();
  const timelock = ITimelock__factory.connect(config.timelock, deployer);
  const timelockAdmin = await timelock.admin();

  let txHash = "";
  if (compare(timelockAdmin, deployer.address)) {
    // If Timelock's admin is deployer, queue the transaction
    const queueTx = await timelock.queueTransaction(
      target,
      value,
      signature,
      ethers.utils.defaultAbiCoder.encode(paramTypes, params),
      eta,
      { ...overrides }
    );
    await queueTx.wait();
  } else if (compare(timelockAdmin, config.opMultiSig)) {
    // If Timelock's admin is OpMultiSig, propose queue tx to OpMultiSig
    if (process.env.DEPLOYER_PRIVATE_KEY === undefined) throw new Error("DEPLOYER_PRIVATE_KEY is not defined");

    const deployerWallet = new ethers.Wallet(
      process.env.DEPLOYER_PRIVATE_KEY,
      new ethers.providers.JsonRpcProvider((network.config as HttpNetworkConfig).url)
    );
    if (!compare(deployerWallet.address, deployer.address)) throw new Error("Delpoyer mismatch");

    const multiSig = new GnosisSafeMultiSigService(chainId, config.opMultiSig, deployerWallet);
    txHash = await multiSig.proposeTransaction(
      timelock.address,
      "0",
      timelock.interface.encodeFunctionData("queueTransaction", [
        target,
        value,
        signature,
        ethers.utils.defaultAbiCoder.encode(paramTypes, params),
        eta,
      ])
    );
  } else {
    throw new Error("Timelock's admin is not deployer or OpMultiSig");
  }
  const paramTypesStr = paramTypes.map((p) => `'${p}'`);
  const paramsStr = params.map((p) => {
    if (Array.isArray(p)) {
      const vauleWithQuote = p.map((p) => {
        if (typeof p === "string") return `'${p}'`;
        return JSON.stringify(p);
      });
      return `[${vauleWithQuote}]`;
    }

    if (typeof p === "string") {
      return `'${p}'`;
    }

    return p;
  });

  const executionTx = `await timelock.executeTransaction('${target}', '${value}', '${signature}', ethers.utils.defaultAbiCoder.encode([${paramTypesStr}], [${paramsStr}]), '${eta}')`;
  console.log(`>> Done.`);
  return {
    chainId,
    info: info,
    queuedAt: txHash,
    executedAt: "",
    executionTransaction: executionTx,
    target,
    value,
    signature,
    paramTypes,
    params,
    eta,
  };
}

export async function executeTransaction(
  chainId: number,
  info: string,
  queuedAt: string,
  executionTx: string,
  target: string,
  value: string,
  signature: string,
  paramTypes: Array<string>,
  params: Array<any>,
  eta: string,
  overrides?: CallOverrides
): Promise<TimelockTransaction> {
  console.log(`>> Execute tx for: ${info}`);
  const config = new ConfigFileHelper().getConfig();
  const timelock = ITimelock__factory.connect(config.timelock, await getDeployer());
  const executeTx = await timelock.executeTransaction(
    target,
    value,
    signature,
    ethers.utils.defaultAbiCoder.encode(paramTypes, params),
    eta,
    overrides
  );
  console.log(`>> Done.`);

  return {
    chainId,
    info: info,
    queuedAt: queuedAt,
    executedAt: executeTx.hash,
    executionTransaction: executionTx,
    target,
    value,
    signature,
    paramTypes,
    params,
    eta,
  };
}
