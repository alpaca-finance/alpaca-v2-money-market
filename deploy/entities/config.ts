import { network } from "hardhat";
import MainnetConfig from "../../.mainnet.json";
import ArbitrumConfig from "../../.arbitrum.mainnet.json";
import { Config } from "../interfaces";

export function getConfig(): Config {
  if (network.name === "mainnet" || network.name === "mainnetfork") {
    return MainnetConfig;
  }
  if (network.name === "arbitrum_mainnet" || network.name === "arbitrum_mainnetfork") {
    return ArbitrumConfig;
  }

  throw new Error("not found config");
}

export function getFilePath(): string {
  if (network.name === "mainnet" || network.name === "mainnetfork") {
    return ".mainnet.json";
  }
  if (network.name === "arbitrum_mainnet" || network.name === "arbitrum_mainnetfork") {
    return ".arbitrum.mainnet.json";
  }

  throw new Error("not found path");
}
