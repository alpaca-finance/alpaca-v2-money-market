#!/bin/bash

source .env

# # build tenderly rpc url
TENDERLY_RPC_URL="https://rpc.tenderly.co/fork/$TENDERLY_FORK_ID"
echo $TENDERLY_RPC_URL

# set account manager as caller ok of native relayer
NATIVE_RELAYER=0xE1D2CA01bc88F325fF7266DD2165944f3CAf0D3D
RELAYER_OWNER=$(cast call $NATIVE_RELAYER --rpc-url $TENDERLY_RPC_URL "owner()" | cut -c 1-2,27-66)
curl --location --request POST $TENDERLY_RPC_URL \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "jsonrpc": "2.0",
    "method": "tenderly_setBalance",
    "params": [
        "'"$RELAYER_OWNER"'",
        "0xFFFFFFFFFFFFFFFFFFFFFFFF"
    ],
    "id": "1234"
}'
cast send $NATIVE_RELAYER --rpc-url $TENDERLY_RPC_URL --from $RELAYER_OWNER "setCallerOk(address[],bool)" "[$LOCAL_ACCOUNT_MANAGER]" true
