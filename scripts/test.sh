#!/bin/bash

source .env

anvil --fork-url $BSC_RPC_URL

cast rpc anvil_setBalance 0xf4a5Fa20dBFA1d956ec87Fe330567a1909c6473b 0x100000000000000000