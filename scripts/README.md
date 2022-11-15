## Solidity Scripting

https://book.getfoundry.sh/tutorials/solidity-scripting


## Commands

RUN `source .env`

`forge script scripts/money-market/deploy/DeployFacet.s.sol:DeployFacet --rpc-url $BSC_RPC_URL --broadcast --unlocked --sender $DEPLOYER`

`fix address`

`forge script scripts/money-market/deploy/DeployDiamond.s.sol:DeployDiamond --rpc-url $BSC_RPC_URL --broadcast --unlocked --sender $DEPLOYER`

`forge script scripts/money-market/deploy/RegisterFacet.s.sol:RegisterFacet --rpc-url $BSC_RPC_URL --broadcast --unlocked --sender $DEPLOYER`



EXAMPLE RUN SCRIPT `forge script scripts/oracle/deploy/SimplePriceOracle.s.sol:MyScript -f $BSC_RPC_URL --broadcast --unlocked --sender $DEPLOYER -vvvv`