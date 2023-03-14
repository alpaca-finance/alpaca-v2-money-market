# Alpaca Finance 2.0

Alpaca Finance 2.0 consists of layers of protocol build on top of the fundamental base layer call Money Market.
Money Market is the set of contracts that allow lenders to deposit the tokens into the platform in exchange for interest. This enables borrowers to utilize this for various financial strategies e.g. hedging, carry trading, etc.
Other Alpaca Finance's protocol that need accesses to capital such as Leverage Yield Farming will also be able
to tap into the same pool of capital. This increases the utilization of lending assets such that the lenders benefit
from providing different uses of loan.

# Contract Architecture

## Money Market

The core contracts are implemented using Diamond Pattern EIP-2535. The protocol facets consist of

- AdminFacet - Configure the protocol
- LendFacet - Start/Stop Lending
- CollateralFacet - Collateral used for over collateralized borrowing
- BorrowFacet - Over collateralized borrowing
- NonCollatFacet - Protocol to Protocol borrowing
- LiquidationFacet - Risk control once the over collateralized borrowing positions became underwater
- ViewFacet - All the view functions

## Glossaries

### Subaccounts

Each address will have a maximum number of subaccounts. This subaccount will be used for overcollateralized borrowing. Each subaccount will be a cross-margin portfilio that enable flexibility to users creating complex strategies

### Collaterals

Collaterals are token that eligible to allow users to borrow other tokens given that the value of collaterals is greater than the value of token borrowed

### Borrowing Power

Under a subaccount, each collateral will have a collateral factor. For example, depositing 1 BTC@$60,000 with a collateral factor of 0.9 will yield 0.9 \* 60,000 = 54,000 Borrowing Power. This is used to calculate how much user can borrow agaist this collateral

Each borrowing token will also have a borrowing factor. For example, borrowing 1000 USDC@$1 with a borrowing factor of 0.8 will use 1000 / 0.8 = 1,250 Borrowing Power.

Follow the above example, this subaccount will have a remaining borrowing power of 54,000 - 1,250 = 52,750

### Repurchasing

Once the remaining borrowing power reach 0, the subaccount is available for repurchasing. Repurchase happened when a repurchaser repay the debt for the subaccount in exchange for collateral under that subaccount at discount price

### Liquidation

If the used borrowing power / total borrowing power is greater than x%, the subaccount is available for liquidation. Liquidation process is done through market selling an collateral at a pre-configured DEX to repay the outstanding debt

### Opening the market

`AdminFacet.openMarket()` This will deploy an interest bearing token, in short ibToken, that represent the share in the lending pool and debtToken that represent the share in over collateralized lending pool

### Lending

To start lending
`LendFacet.deposit()` Supply the token to mint the ibToken
To withdraw
`LendFacet.withdraw()` Burn the ibToken to get the deposited token back with interest

### Overcollateralized Borrowing

To add collateral to the subaccount
`CollateralFacet.addCollateral()` - Add a token as a collateral
To borrow a token
`BorrowFacet.borrow()` - Borrowing a token

### Liquidation

To repurchase
`LiquidationFacet.repurchase()` - Repurchase an underwater subaccount
To liquidate
`LiquidationFacet.liquidationCall()` - Liquidate an underwater subaccount

# Setting up the project

- Install dependencies
  `yarn`
- to install forge, cast and anvil
  `curl -L https://foundry.paradigm.xyz | bash`
- To compile contracts
  `forge build`

# Testing

```
forge test
```

# Deployment

### Prerequisite

- Foundry installed
- Setup deployment config file in `./configs/[filename].json`
- Setup `.env` with `DEPLOYER_PRIVATE_KEY`, `RPC_URL`, and `DEPLOYMENT_CONFIG_FILENAME`
- Load `.env` with command `source .env`

### Money market

**To simulate the deployment script**

```bash
forge script solidity/scripts/deployments/01_DeployMoneyMarket.s.sol
```

**To simulate with the real network**

```
`forge script solidity/scripts/deployments/01_DeployMoneyMarket.s.sol --rpc-url $RPC_URL`
```

**To execute the real transactions**

```
`forge script solidity/scripts/deployments/01_DeployMoneyMarket.s.sol --rpc-url $RPC_URL --broadcast`
```

To make it work on Tenderly, add flag `--slow` for it wait for tx to be confirmed before submit next tx

## Utility scripts

### Prerequisite

- Foundry installed
- Setup deployment config file in `./configs/[filename].json`
- Setup `.env` with `DEPLOYER_PRIVATE_KEY`, `RPC_URL`, and `DEPLOYMENT_CONFIG_FILENAME`
- Load `.env` with command `source .env`
- have deployed contract addresses set in config file
- for each script, you can set config values in script file in the inputs section

**Dry run locally**

```
forge script solidity/scripts/utilities/ScriptName.s.sol --sig "runLocal()"
```

**To simulate with the real network**

```
forge script solidity/scripts/utilities/ScriptName.s.sol --rpc-url $RPC_URL
```

**To execute the real transactions**

```
forge script solidity/scripts/utilities/ScriptName.s.sol --broadcast --rpc-url $RPC_URL
```

# Licensing

The primary license for Alpaca Protocol 2.0 is the BUSL LICENSE, see [BUSL LICENSE](https://github.com/alpaca-finance/alpaca-v2-money-market/blob/main/LICENSE).
