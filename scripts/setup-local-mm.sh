#!/bin/bash
source .env

DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0xFFFFFFFFFFFFFFFFFFFFFFFF

USER_ADDRESS=$(cast wallet address --private-key $USER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $USER_ADDRESS 0xFFFFFFFFFFFFFFFFFFFFFFFF

# seed user address with tokens from rich account
HUNDRED_ETHER=100000000000000000000
# pstake
cast rpc anvil_impersonateAccount 0x680b04c3CF0422679580F53C34B4839b24d141D3
cast send 0x4C882ec256823eE773B25b414d36F92ef58a7c0C --from 0x680b04c3CF0422679580F53C34B4839b24d141D3 "transfer(address,uint256)" $USER_ADDRESS $HUNDRED_ETHER
# dodo
cast rpc anvil_impersonateAccount 0x3e19d726ed435AfD3A42967551426b3A47c0F5b7
cast send 0x67ee3Cb086F8a16f34beE3ca72FAD36F7Db929e2 --from 0x3e19d726ed435AfD3A42967551426b3A47c0F5b7 "transfer(address,uint256)" $USER_ADDRESS $HUNDRED_ETHER
# busd
cast rpc anvil_impersonateAccount 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa
cast send 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --from 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa "transfer(address,uint256)" $USER_ADDRESS $HUNDRED_ETHER
# wrap bnb
cast rpc anvil_impersonateAccount $USER_ADDRESS
cast send 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c --from $USER_ADDRESS --value $HUNDRED_ETHER "deposit()"
cast rpc anvil_stopImpersonatingAccount $USER_ADDRESS

# save snapshot before deployment to facilitate chain state reversion
cast rpc evm_snapshot

forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/04_DeployMoneyMarketReader.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/deployments/05_DeployMoneyMarketAccountManager.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
