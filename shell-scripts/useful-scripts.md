read contract

```
cast call $READER_ADDRESS "getSubAccountSummary(address,uint256)" 0xaddress 0
```

write contract

```
cast send $CONTRACT_ADDRESS "depositAndAddCollateral(uint256,address,uint256)" 0 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56 10000000000000000 --private-key $PRIVATE_KEY
```

prettify json

```
json_pp
```

see mempool

```
cast rpc txpool_status | json_pp
cast rpc txpool_inspect | json_pp
cast rpc txpool_content | json_pp
```

revert to snapshot currently snapshotted after deploy script finish
0x0 is snapshot id
reverting will delete snapshot
return boolean indicate if it succeeded or not

```
cast rpc evm_revert 0x0
```
