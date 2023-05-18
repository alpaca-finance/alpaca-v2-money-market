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
