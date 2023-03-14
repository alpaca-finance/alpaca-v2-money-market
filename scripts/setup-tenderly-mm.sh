#!/bin/bash

# load .env
source .env

# get addresses from private key
DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
echo $DEPLOYER_ADDRESS
USER_ADDRESS=$(cast wallet address --private-key $USER_PRIVATE_KEY | cut -d ' ' -f 2)
echo $USER_ADDRESS

# build tenderly rpc url
TENDERLY_RPC_URL="https://rpc.tenderly.co/fork/$TENDERLY_FORK_ID"
echo $TENDERLY_RPC_URL

# seed address with native currency
curl --location --request POST $TENDERLY_RPC_URL \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "jsonrpc": "2.0",
    "method": "tenderly_setBalance",
    "params": [
        "'"$DEPLOYER_ADDRESS"'",
        "0xFFFFFFFFFFFFFFFFFFFFFFFF"
    ],
    "id": "1234"
}'
curl --location --request POST $TENDERLY_RPC_URL \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "jsonrpc": "2.0",
    "method": "tenderly_setBalance",
    "params": [
        "'"$USER_ADDRESS"'",
        "0xFFFFFFFFFFFFFFFFFFFFFFFF"
    ],
    "id": "1234"
}'

# seed user address with tokens from rich account
THOUSAND_ETHER=1000000000000000000000
# pstake
cast send 0x4C882ec256823eE773B25b414d36F92ef58a7c0C --rpc-url $TENDERLY_RPC_URL --from 0x680b04c3CF0422679580F53C34B4839b24d141D3 "transfer(address,uint256)" $USER_ADDRESS $THOUSAND_ETHER
# dodo
cast send 0x67ee3Cb086F8a16f34beE3ca72FAD36F7Db929e2 --rpc-url $TENDERLY_RPC_URL --from 0x3e19d726ed435AfD3A42967551426b3A47c0F5b7 "transfer(address,uint256)" $USER_ADDRESS $THOUSAND_ETHER
# busd
cast send 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 --rpc-url $TENDERLY_RPC_URL --from 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa "transfer(address,uint256)" $USER_ADDRESS $THOUSAND_ETHER
# wrap bnb
cast send 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c --rpc-url $TENDERLY_RPC_URL --from $USER_ADDRESS --value $THOUSAND_ETHER "deposit()"

# send alpaca to deployer to be used in miniFL setup
cast send 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F --rpc-url $TENDERLY_RPC_URL --from 0x000000000000000000000000000000000000dEaD "transfer(address,uint256)" $DEPLOYER_ADDRESS $THOUSAND_ETHER

# retry command until pass

echo "🚧 deploying proxy admin"
forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying proxy admin deployment"
    forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 deploying minFL"
forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying minFL deployment"
    forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 deploying money market"
forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying money market deployment"
    forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 deploying money market account manager"
forge script solidity/scripts/deployments/04_DeployMoneyMarketAccountManager.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying money market account manager deployment"
    forge script solidity/scripts/deployments/04_DeployMoneyMarketAccountManager.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 deploying money market reader"
forge script solidity/scripts/deployments/05_DeployMoneyMarketReader.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying money market reader deployment"
    forge script solidity/scripts/deployments/05_DeployMoneyMarketReader.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 deploying oracle"
forge script solidity/scripts/deployments/06_DeployOracle.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying oracle deployment"
    forge script solidity/scripts/deployments/06_DeployOracle.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 setting mm state for test"
forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retry setting mm state for test"
    forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

sleep 3

echo "🚧 setting up miniFL for test"
forge script solidity/scripts/utilities/SetUpMiniFLForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retry setting up miniFL for test"
    forge script solidity/scripts/utilities/SetUpMiniFLForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done
