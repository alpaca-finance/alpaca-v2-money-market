source .env
forge script solidity/scripts/deployments/01_DeployMoneyMarketFacets.s.sol --broadcast --rpc-url $RPC_URL
forge script solidity/scripts/deployments/02_DeployMoneyMarketDiamond.s.sol --broadcast --rpc-url $RPC_URL
forge script solidity/scripts/deployments/03_MoneyMarketDiamondCut.s.sol --broadcast --rpc-url $RPC_URL