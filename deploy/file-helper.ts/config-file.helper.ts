import { Config, InterestModel, Market, MiniFLPool, MoneyMarketFacet, Rewarder } from "../interfaces";
import * as fs from "fs";
import { getConfig, getFilePath } from "../entities/config";

export class ConfigFileHelper {
  private filePath: string;
  private config: Config;
  constructor() {
    this.config = getConfig();
    this.filePath = getFilePath();
  }

  public addNewMarket(market: Market): void {
    this.config.moneyMarket.markets.push(market);
    this._writeConfigFile(this.config);
  }

  public addMiniFLPool(pool: MiniFLPool): void {
    this.config.miniFL.pools.push(pool);
    this._writeConfigFile(this.config);
  }

  public setMiniFLPoolRewarders(pid: number, rewarderAddresses: string[]): void {
    const miniFLPool = this.config.miniFL.pools.find((pool) => pool.id === Number(pid))!;

    const rewarders = rewarderAddresses.map(
      (rewarder) => this.config.rewarders.find((configRewarder) => configRewarder.address === rewarder)!
    );
    miniFLPool.rewarders = rewarders;
    this._writeConfigFile(this.config);
  }

  public setAlpacaV2Oracle02(address: string): void {
    this.config.oracle.alpacaV2Oracle02 = address;
    this._writeConfigFile(this.config);
  }

  public setDebtToken(address: string): void {
    this.config.moneyMarket.debtTokenImplementation = address;
    this._writeConfigFile(this.config);
  }

  public setInterestModels(interestModel: InterestModel): void {
    this.config.sharedConfig = interestModel;
    this._writeConfigFile(this.config);
  }

  public setInterestBearingToken(address: string): void {
    this.config.moneyMarket.interestBearingTokenImplementation = address;
    this._writeConfigFile(this.config);
  }

  public setMiniFLPoolDeploy(proxy: string, implementation: string): void {
    this.config.miniFL.proxy = proxy;
    this.config.miniFL.implementation = implementation;
    this._writeConfigFile(this.config);
  }

  public setMoneyMarketDiamondDeploy(facets: MoneyMarketFacet, address: string): void {
    this.config.moneyMarket.moneyMarketDiamond = address;
    this.config.moneyMarket.facets = facets;
    this._writeConfigFile(this.config);
  }

  public setMoneyMarketAccountManagerDeploy(proxy: string, implementation: string): void {
    this.config.moneyMarket.accountManager.proxy = proxy;
    this.config.moneyMarket.accountManager.implementation = implementation;
    this._writeConfigFile(this.config);
  }

  public setOracleMedianizer(address: string): void {
    this.config.oracle.oracleMedianizer = address;
    this._writeConfigFile(this.config);
  }

  public setFixedFeeModel500Bps(address: string): void {
    this.config.sharedConfig.fixFeeModel500Bps = address;
    this._writeConfigFile(this.config);
  }

  public addRewarder(rewarder: Rewarder): void {
    this.config.rewarders.push(rewarder);
    this._writeConfigFile(this.config);
  }

  public getConfig() {
    return this.config;
  }

  private _writeConfigFile(config: Config) {
    console.log(`>> Writing ${this.filePath}`);
    fs.writeFileSync(this.filePath, JSON.stringify(config, null, 2));
    console.log("✅ Done");
  }
}
