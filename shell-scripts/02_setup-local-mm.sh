#!/bin/bash
source .env

DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0xFFFFFFFFFFFFFFFFFFFFFFFF

USER_ADDRESS=$(cast wallet address --private-key $USER_PRIVATE_KEY | cut -d ' ' -f 2)
cast rpc anvil_setBalance $USER_ADDRESS 0xFFFFFFFFFFFFFFFFFFFFFFFF

# seed user address with tokens from rich account
THOUSAND_ETHER=1000000000000000000000
# doge (8 decimals)
cast rpc anvil_impersonateAccount 0x0000000000000000000000000000000000001004
cast send 0xbA2aE424d960c26247Dd6c32edC70B295c744C43 --from 0x0000000000000000000000000000000000001004 "transfer(address,uint256)" $USER_ADDRESS 100000000000000
# dodo
cast rpc anvil_impersonateAccount 0x3e19d726ed435AfD3A42967551426b3A47c0F5b7
cast send 0x67ee3Cb086F8a16f34beE3ca72FAD36F7Db929e2 --from 0x3e19d726ed435AfD3A42967551426b3A47c0F5b7 "transfer(address,uint256)" $USER_ADDRESS $THOUSAND_ETHER
# busd
cast rpc anvil_impersonateAccount 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3
cast send 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --from 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3 "transfer(address,uint256)" $USER_ADDRESS $THOUSAND_ETHER
# wrap bnb
cast rpc anvil_impersonateAccount $USER_ADDRESS
cast send 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c --from $USER_ADDRESS --value $THOUSAND_ETHER "deposit()"

# send alpaca to deployer to be used in miniFL setup
cast rpc anvil_impersonateAccount 0x000000000000000000000000000000000000dEaD
cast send 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F --from 0x000000000000000000000000000000000000dEaD "transfer(address,uint256)" $DEPLOYER_ADDRESS $THOUSAND_ETHER

# set price sources
USD=0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff
ALPACA_DEPLOYER=0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51
cast rpc anvil_setBalance $ALPACA_DEPLOYER 0xFFFFFFFFFFFFFFFFFFFFFFFF
cast rpc anvil_impersonateAccount $ALPACA_DEPLOYER
# set price feeds for busd, dodo, doge
CHAINLINK_ORACLE=0x634902128543b25265da350e2d961C7ff540fC71
cast send $CHAINLINK_ORACLE --from $ALPACA_DEPLOYER "setPriceFeeds(address[],address[],address[])" [0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56,0x67ee3Cb086F8a16f34beE3ca72FAD36F7Db929e2,0xbA2aE424d960c26247Dd6c32edC70B295c744C43] "[$USD,$USD,$USD]" [0xcBb98864Ef56E9042e7d2efef76141f15731B82f,0x87701B15C08687341c2a847ca44eCfBc8d7873E1,0x3AB0A0d137D4F946fBB19eecc6e92E64660231C8]
# assign chainlink price oracle
MEDIANIZER=0x553b8adc2Ac16491Ec57239BeA7191719a2B880c
MAX_PRICE_DEVIATION=1000000000000000000
MAX_PRICE_STALE=86400
# busd
cast send $MEDIANIZER --from $ALPACA_DEPLOYER "setPrimarySources(address,address,uint256,uint256,address[])" 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 $USD $MAX_PRICE_DEVIATION $MAX_PRICE_STALE "[$CHAINLINK_ORACLE]"
# dodo
cast send $MEDIANIZER --from $ALPACA_DEPLOYER "setPrimarySources(address,address,uint256,uint256,address[])" 0x67ee3Cb086F8a16f34beE3ca72FAD36F7Db929e2 $USD $MAX_PRICE_DEVIATION $MAX_PRICE_STALE "[$CHAINLINK_ORACLE]"
# doge
cast send $MEDIANIZER --from $ALPACA_DEPLOYER "setPrimarySources(address,address,uint256,uint256,address[])" 0xbA2aE424d960c26247Dd6c32edC70B295c744C43 $USD $MAX_PRICE_DEVIATION $MAX_PRICE_STALE "[$CHAINLINK_ORACLE]"
cast rpc anvil_stopImpersonatingAccount $ALPACA_DEPLOYER

# save snapshot before deployment to facilitate chain state reversion
cast rpc evm_snapshot

forge script script/deployments/01_DeployProxyAdmin.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/deployments/02_DeployMiniFL.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/deployments/03_DeployMoneyMarket.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/deployments/04_DeployMoneyMarketAccountManager.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/deployments/05_DeployMoneyMarketReader.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/deployments/06_DeployOracle.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/utilities/SetUpMMForTest.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
forge script script/utilities/SetUpMiniFLForTest.s.sol --rpc-url $LOCAL_RPC_URL --broadcast
