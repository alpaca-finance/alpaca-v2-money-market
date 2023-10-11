interface UpgradableContract {
  implementation: string;
  proxy: string;
}

interface AccountManager extends UpgradableContract {}

export interface Config {
  usdPlaceholder: string;
  moneyMarket: MoneyMarket;
  sharedConfig: SharedConfig;
  tokens: Tokens;
  miniFL: MiniFL;
  rewarders: Rewarder[];
  proxyAdmin: string;
  timelock: string;
  opMultiSig: string;
  oracle: Oracle;
}

interface Tokens {
  wbeth: string;
}

interface SharedConfig {
  fixFeeModel500Bps: string;
  doubleSlope1: string;
  doubleSlope2: string;
  doubleSlope3: string;
  flatSlope1: string;
  flatSlope2: string;
}

export interface Oracle {
  alpacaV2Oracle: string;
  alpacaV2Oracle02: string;
  chainlinkOracle: string;
  oracleMedianizer: string;
  simpleOracle: string;
}

export interface MoneyMarket {
  moneyMarketDiamond: string;
  facets: {
    adminFacet: string;
    borrowFacet: string;
    collateralFacet: string;
    diamondCutFacet: string;
    diamondLoupeFacet: string;
    flashloanFacet: string;
    lendFacet: string;
    liquidationFacet: string;
    nonCollatBorrowFacet: string;
    ownershipFacet: string;
    viewFacet: string;
  };
  markets: Market[];
  accountManager: AccountManager;
}

export interface MiniFL {
  proxy: string;
  pools: MiniFLPool[];
}

export interface Market {
  name: string;
  tier: string;
  token: string;
  ibToken: string;
  debtToken: string;
  interestModel: string;
}

export interface MiniFLPool {
  id: number;
  name: string;
  stakingToken: string;
  rewarders: Rewarder[];
}

export interface Rewarder {
  name: string;
  address: string;
  rewardToken: string;
}

export enum AssetTier {
  UNLISTED = 0,
  ISOLATE = 1,
  CROSS = 2,
  COLLATERAL = 3,
}

export const reverseAssetTier: Record<AssetTier, keyof typeof AssetTier> = {
  0: "UNLISTED",
  1: "ISOLATE",
  2: "CROSS",
  3: "COLLATERAL",
};

export interface TimelockTransaction {
  info: string;
  chainId: number;
  queuedAt: string;
  executedAt: string;
  executionTransaction: string;
  target: string;
  value: string;
  signature: string;
  paramTypes: Array<string>;
  params: Array<any>;
  eta: string;
}
