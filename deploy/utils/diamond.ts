import { ContractFactory } from "ethers";
import _ from "lodash";
import { ConfigFileHelper } from "../file-helper.ts/config-file.helper";

export function getSelectors(contract: ContractFactory): Array<string> {
  const signatures = Object.keys(contract.interface.functions);
  const selectors = signatures.reduce((acc, val) => {
    acc.push(contract.interface.getSighash(val));
    return acc;
  }, [] as Array<string>);
  return selectors;
}

export function facetContractNameToAddress(contractName: string): string {
  const config = new ConfigFileHelper().getConfig();
  const facetList = config.moneyMarket.facets as any;
  contractName = _.camelCase(contractName);
  const address = facetList[contractName];
  if (!address) {
    throw new Error(`${contractName} not found in config`);
  }
  return address;
}

export function getAdminFacetSelectors(): string[] {
  return [
    "openMarket(address,(uint8,uint16,uint16,uint256,uint256),(uint8,uint16,uint16,uint256,uint256))",
    "setAccountManagersOk(address[],bool)",
    "setDebtTokenImplementation(address)",
    "setEmergencyPaused(bool)",
    "setFees(uint16,uint16,uint16)",
    "setFlashloanParams(uint16,uint16,address)",
    "setIbTokenImplementation(address)",
    "setInterestModel(address,address)",
    "setLiquidationParams(uint16,uint16)",
    "setLiquidationStratsOk(address[],bool)",
    "setLiquidationTreasury(address)",
    "setLiquidatorsOk(address[],bool)",
    "setMaxNumOfToken(uint8,uint8,uint8)",
    "setMinDebtSize(uint256)",
    "setNonCollatBorrowerOk(address,bool)",
    "setNonCollatInterestModel(address,address,address)",
    "setOperatorsOk(address[],bool)",
    "setOracle(address)",
    "setProtocolConfigs((address,(address,uint256)[],uint256)[])",
    "setRepurchaseRewardModel(address)",
    "setRiskManagersOk(address[],bool)",
    "setTokenConfigs(address[],(uint8,uint16,uint16,uint256,uint256)[])",
    "setTokenMaximumCapacities(address,uint256,uint256)",
    "topUpTokenReserve(address,uint256)",
    "withdrawProtocolReserves((address,address,uint256)[])",
  ];
}

export function getBorrowFacetSelectors(): string[] {
  return [
    "accrueInterest(address)",
    "borrow(address,uint256,address,uint256)",
    "repay(address,uint256,address,uint256)",
    "repayWithCollat(address,uint256,address,uint256)",
  ];
}

export function getCollateralFacetSelectors(): string[] {
  return [
    "addCollateral(address,uint256,address,uint256)",
    "removeCollateral(address,uint256,address,uint256)",
    "transferCollateral(address,uint256,uint256,address,uint256)",
  ];
}

export function getMMDiamondLoupeFacetSelectors(): string[] {
  return [
    "facetAddress(bytes4)",
    "facetAddresses()",
    "facetFunctionSelectors(address)",
    "facets()",
    "supportsInterface(bytes4)",
  ];
}

export function getFlashloanFacetSelectors(): string[] {
  return ["flashloan(address,uint256,bytes)"];
}

export function getLendFacetSelectors(): string[] {
  return ["deposit(address,address,uint256)", "withdraw(address,address,uint256)"];
}

export function getLiquidationFacetSelectors(): string[] {
  return [
    "liquidationCall(address,address,uint256,address,address,uint256,uint256,bytes)",
    "repurchase(address,uint256,address,address,uint256)",
  ];
}

export function getNonCollatBorrowFacetSelectors(): string[] {
  return ["nonCollatBorrow(address,uint256)", "nonCollatRepay(address,address,uint256)"];
}

export function getOwnershipFacetSelectors(): string[] {
  return ["acceptOwnership()", "owner()", "pendingOwner()", "transferOwnership(address)"];
}

export function getViewFacetSelectors(): string[] {
  return [
    "getAllSubAccountCollats(address,uint256)",
    "getCollatAmountOf(address,uint256,address)",
    "getDebtLastAccruedAt(address)",
    "getDebtTokenFromToken(address)",
    "getDebtTokenImplementation()",
    "getFeeParams()",
    "getFlashloanParams()",
    "getFloatingBalance(address)",
    "getGlobalDebtValue(address)",
    "getGlobalDebtValueWithPendingInterest(address)",
    "getGlobalPendingInterest(address)",
    "getIbTokenFromToken(address)",
    "getIbTokenImplementation()",
    "getLiquidationParams()",
    "getLiquidationTreasury()",
    "getMaxNumOfToken()",
    "getMinDebtSize()",
    "getMiniFL()",
    "getMiniFLPoolIdOfToken(address)",
    "getNonCollatAccountDebt(address,address)",
    "getNonCollatAccountDebtValues(address)",
    "getNonCollatBorrowingPower(address)",
    "getNonCollatInterestRate(address,address)",
    "getNonCollatPendingInterest(address,address)",
    "getNonCollatTokenDebt(address)",
    "getOracle()",
    "getOverCollatDebtShareAndAmountOf(address,uint256,address)",
    "getOverCollatDebtSharesOf(address,uint256)",
    "getOverCollatInterestModel(address)",
    "getOverCollatInterestRate(address)",
    "getOverCollatPendingInterest(address)",
    "getOverCollatTokenDebt(address)",
    "getOverCollatTokenDebtShares(address)",
    "getOverCollatTokenDebtValue(address)",
    "getProtocolReserve(address)",
    "getRepurchaseRewardModel()",
    "getSubAccount(address,uint256)",
    "getTokenConfig(address)",
    "getTokenFromIbToken(address)",
    "getTotalBorrowingPower(address,uint256)",
    "getTotalCollat(address)",
    "getTotalNonCollatUsedBorrowingPower(address)",
    "getTotalToken(address)",
    "getTotalTokenWithPendingInterest(address)",
    "getTotalUsedBorrowingPower(address,uint256)",
    "isAccountManagersOk(address)",
    "isLiquidationStratOk(address)",
    "isLiquidatorOk(address)",
    "isOperatorsOk(address)",
    "isRiskManagersOk(address)",
  ];
}
