import { Config, Market, MiniFLPool, Rewarder } from "../interfaces";
import MainnetConfig from "../../.mainnet.json";
import * as fs from "fs";

export class ConfigFileHelper {
  private filePath: string;
  private config: Config;
  constructor() {
    this.filePath = ".mainnet.json";
    this.config = MainnetConfig;
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
