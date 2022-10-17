import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    // rinkeby: {
    //   url: process.env.RINKEBY_RPC,
    //   accounts:
    //     process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    // },
  },
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "istanbul",
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "./typechain",
    target: process.env.TYPECHAIN_TARGET || "ethers-v5",
  },
  mocha: {
    timeout: 100000,
  },
};
