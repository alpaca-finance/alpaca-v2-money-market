#!/bin/bash
source .env
DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x100000000000000000
forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/04_DeployMoneyMarketReader.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/05_DeployMoneyMarketAccountManager.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
cast rpc evm_mine
