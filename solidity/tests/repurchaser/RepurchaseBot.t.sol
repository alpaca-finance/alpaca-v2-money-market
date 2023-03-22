// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "solidity/tests/utils/Components.sol";

import { PancakeV2FlashLoanRepurchaser } from "solidity/contracts/repurchaser/PancakeV2FlashLoanRepurchaser.sol";
import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";
import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";
import { IPancakeRouter01 } from "solidity/contracts/repurchaser/interfaces/IPancakeRouter01.sol";
import { IPancakePair } from "solidity/contracts/repurchaser/interfaces/IPancakePair.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
contract PancakeV2FlashLoanRepurchaserTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  PancakeV2FlashLoanRepurchaser internal pancakeV2FlashLoanRepurchaser;

  // update these addresses once you deploy new fork
  IMoneyMarket internal moneyMarket = IMoneyMarket(0x9B1afC17cF5DD3d216B0d2e7eBbc82D61a2f3629);
  IMoneyMarketAccountManager internal accountManager =
    IMoneyMarketAccountManager(0xb21Ec6AE6e9f95CA8b8f8f839B9d348C3c65B572);
  IAlpacaV2Oracle internal oracle = IAlpacaV2Oracle(0xA26EFf35729E1D7D5e91fa0F5eA747cCd1aCbE11);

  address internal DEPLOYER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal USER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  uint256 internal SUBACCOUNT_ID = 255; // to not collide with existing subAccount setup from script

  IPancakeRouter01 internal pancakeRouter = IPancakeRouter01(0x10ED43C718714eb63d5aA57B78B54704E256024E);
  IERC20 internal doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);
  IERC20 internal busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

  function setUp() public {
    pancakeV2FlashLoanRepurchaser = new PancakeV2FlashLoanRepurchaser(
      address(moneyMarket),
      address(accountManager),
      address(pancakeRouter)
    );

    // TODO: move these to setup script
    vm.startPrank(DEPLOYER);

    moneyMarket.setMinDebtSize(0);

    // can liquidate up to 50% of used borrowing power
    moneyMarket.setLiquidationParams(5000, 11000);

    address[] memory repurchasers = new address[](1);
    repurchasers[0] = address(pancakeV2FlashLoanRepurchaser);
    moneyMarket.setRepurchasersOk(repurchasers, true);

    moneyMarket.setRepurchaseRewardModel(new FixedFeeModel());

    moneyMarket.setLiquidationTreasury(address(this));
    vm.stopPrank();
  }

  function testCorrectness_PancakeV2FlashLoanRepurchaser() public {
    // get price from oracle
    (uint256 dogePrice, ) = oracle.getTokenPrice(address(doge));
    (uint256 busdPrice, ) = oracle.getTokenPrice(address(busd));

    // calculate how many doge can we max borrow with 1 BUSD collat
    LibConstant.TokenConfig memory dogeTokenConfig = moneyMarket.getTokenConfig(address(doge));
    address ibBusd = moneyMarket.getIbTokenFromToken(address(busd));
    LibConstant.TokenConfig memory ibBusdTokenConfig = moneyMarket.getTokenConfig(ibBusd);
    uint256 maxBorrowDoge = ((1e8 * (busdPrice * ibBusdTokenConfig.collateralFactor)) / LibConstant.MAX_BPS) /
      ((dogePrice * LibConstant.MAX_BPS) / dogeTokenConfig.borrowingFactor);

    vm.startPrank(USER);

    // seed money market
    accountManager.deposit(address(doge), 100e8);

    // make position
    accountManager.depositAndAddCollateral(SUBACCOUNT_ID, address(busd), 1 ether);
    accountManager.borrow(SUBACCOUNT_ID, address(doge), maxBorrowDoge);

    vm.stopPrank();

    // mockCall price at oracle to make position underwater
    // note that price on dex is not affected
    uint256 newDogePrice = (dogePrice * 105) / 100;
    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(IAlpacaV2Oracle.getTokenPrice.selector, address(doge)),
      abi.encode(newDogePrice, block.timestamp)
    );

    // repurchase 10% of debt
    uint256 repurchaseAmount = maxBorrowDoge / 10;
    address[] memory path = new address[](2);
    path[0] = address(busd);
    path[1] = address(doge);
    bytes memory data = abi.encode(USER, SUBACCOUNT_ID, address(doge), address(busd), ibBusd, repurchaseAmount, path);
    // have to flashloan repurchaseAmount of doge
    // doge is token0, busd is token1
    IPancakePair(0xE27859308ae2424506D1ac7BF5bcb92D6a73e211).swap(
      repurchaseAmount,
      0,
      address(pancakeV2FlashLoanRepurchaser),
      data
    );
  }
}
