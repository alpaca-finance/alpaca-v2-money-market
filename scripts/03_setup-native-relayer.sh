#!/bin/bash
source .env

# set account manager as caller ok of native relayer
NATIVE_RELAYER=0xE1D2CA01bc88F325fF7266DD2165944f3CAf0D3D
RELAYER_OWNER=$(cast call $NATIVE_RELAYER "owner()" | cut -c 1-2,27-66)
cast rpc anvil_setBalance $RELAYER_OWNER 0xFFFFFFFFFFFFFFFFFFFFFFFF
cast rpc anvil_impersonateAccount $RELAYER_OWNER
cast send $NATIVE_RELAYER --from $RELAYER_OWNER "setCallerOk(address[],bool)" "[$LOCAL_ACCOUNT_MANAGER]" true