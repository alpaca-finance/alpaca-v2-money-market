# AlpacaV2 Money Market

## Set up

1. `yarn`
2. `foundryup` to install forge, cast and anvil
3. `forge build` to compile contracts

## Deploy

### Prerequisite

- Have Foundry installed
- Setup `.env` with `DEPLOYER_PRIVATE_KEY` and `RPC_URL`
- Load `.env` with command `source .env`

### Money market

```bash
forge script solidity/deployments/scripts/DeployMoneyMarket.s.sol
```

This command will dry run locally (not deployed yet)

- Add flag `--rpc-url $RPC_URL` to simulate deployment to network (not deployed yet)
- Add flag `--broadcast` to signed and broadcast tx to network (will deploy)
  - To make it work on Tenderly, add flag `--slow` for it wait for tx to be confirmed before submit next tx
