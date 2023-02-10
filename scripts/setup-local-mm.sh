#!/bin/bash
source .env
DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x100000000000000000
forge script solidity/scripts/deployments/01_DeployMoneyMarket.s.sol --rpc-url $RPC_URL --broadcast
forge script solidity/scripts/deployments/DeployMoneyMarketReader.s.sol --rpc-url $RPC_URL --broadcast
forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $RPC_URL --broadcast
