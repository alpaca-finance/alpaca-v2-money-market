#!/bin/bash

# load .env
source .env

# get address from private key
DEPLOYER_ADDRESS=$(cast wallet address --private-key $DEPLOYER_PRIVATE_KEY | cut -d ' ' -f 2)
echo $DEPLOYER_ADDRESS

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
        "0xDE0B6B3A7640000000000"
    ],
    "id": "1234"
}'

# retry command until pass

echo "🚧 deploying proxy admin"
forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying proxy admin deployment"
    forge script solidity/scripts/deployments/01_DeployProxyAdmin.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

echo "🚧 deploying minFL"
forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying minFL deployment"
    forge script solidity/scripts/deployments/02_DeployMiniFL.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

echo "🚧 deploying money market"
forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying money market deployment"
    forge script solidity/scripts/deployments/03_DeployMoneyMarket.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

echo "🚧 deploying money market reader"
forge script solidity/scripts/deployments/04_DeployMoneyMarketReader.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retrying money market reader deployment"
    forge script solidity/scripts/deployments/04_DeployMoneyMarketReader.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done

echo "🚧 setting mm state for test"
forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow
while [[ $? -ne 0 ]]; do
    echo "🙉 retry setting mm state for test"
    forge script solidity/scripts/utilities/SetUpMMForTest.s.sol --rpc-url $TENDERLY_RPC_URL --broadcast --slow --resume
    sleep 2
done
