// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "solidity/tests/utils/Components.sol";

import { FixedFeeModel } from "solidity/contracts/money-market/fee-models/FixedFeeModel.sol";

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { IFeeModel } from "solidity/contracts/money-market/interfaces/IFeeModel.sol";

import { IUniswapV3Pool } from "solidity/contracts/repurchaser/interfaces/IUniswapV3Pool.sol";
import { UniswapV3FlashloanRepurchaser } from "solidity/contracts/repurchaser/UniswapV3FlashloanRepurchaser.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
contract UniswapV3FlashLoanRepurchaserTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  UniswapV3FlashloanRepurchaser internal uniV3FlashLoanRepurchaser;
  FixedFeeModel internal feeModel;

  // update these addresses once you deploy new fork
  IMoneyMarket internal moneyMarket = IMoneyMarket(0xF15C0325C2A3007918904E336a92dB94A6E85FD2);
  IMoneyMarketAccountManager internal accountManager =
    IMoneyMarketAccountManager(0x6b99c180fc655a778Ddc98e8688896AfCF3BF954);
  IAlpacaV2Oracle internal oracle = IAlpacaV2Oracle(0xb302411bd1e3b786afC1C235Fc305F23F101027f);

  address internal DEPLOYER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal USER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  uint256 internal SUBACCOUNT_ID = 255; // to not collide with existing subAccount setup from script

  IUniswapV3Pool internal uniV3Pool = IUniswapV3Pool(0x32776Ed4D96ED069a2d812773F0AD8aD9Ef83CF8);
  IERC20 internal wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 internal busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

  function setUp() public {
    uniV3FlashLoanRepurchaser = new UniswapV3FlashloanRepurchaser(
      address(this),
      address(moneyMarket),
      address(accountManager)
    );

    // TODO: move these to setup script
    vm.startPrank(DEPLOYER);

    moneyMarket.setMinDebtSize(0);

    // can liquidate up to 50% of used borrowing power
    moneyMarket.setLiquidationParams(5000, 11000);

    feeModel = new FixedFeeModel();
    moneyMarket.setRepurchaseRewardModel(feeModel);

    moneyMarket.setLiquidationTreasury(address(this));
    vm.stopPrank();
  }

  function testCorrectness_UniswapV3FlashLoanRepurchaser() public {
    // get price from oracle
    (uint256 bnbPrice, ) = oracle.getTokenPrice(address(wbnb));
    (uint256 busdPrice, ) = oracle.getTokenPrice(address(busd));

    // calculate how many wbnb can we max borrow with 1 BUSD collat
    LibConstant.TokenConfig memory wbnbTokenConfig = moneyMarket.getTokenConfig(address(wbnb));
    address ibBusd = moneyMarket.getIbTokenFromToken(address(busd));
    LibConstant.TokenConfig memory ibBusdTokenConfig = moneyMarket.getTokenConfig(ibBusd);
    uint256 maxBorrowBnb = ((1e18 * (busdPrice * ibBusdTokenConfig.collateralFactor)) / LibConstant.MAX_BPS) /
      ((bnbPrice * LibConstant.MAX_BPS) / wbnbTokenConfig.borrowingFactor);

    vm.startPrank(USER);

    // seed money market
    accountManager.deposit(address(wbnb), 100e8);

    // make position
    accountManager.depositAndAddCollateral(SUBACCOUNT_ID, address(busd), 1 ether);
    accountManager.borrow(SUBACCOUNT_ID, address(wbnb), maxBorrowBnb);

    vm.stopPrank();

    // mockCall price at oracle to make position underwater
    // note that price on dex is not affected
    uint256 newBnbPrice = (bnbPrice * 10001) / 10000;
    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(IAlpacaV2Oracle.getTokenPrice.selector, address(wbnb)),
      abi.encode(newBnbPrice, block.timestamp)
    );

    // repurchase 10% of debt
    uint256 repurchaseAmount = maxBorrowBnb / 10;

    // bytes memory data = abi.encode(0);
    bytes memory data = abi.encode(USER, SUBACCOUNT_ID, address(wbnb), address(busd), ibBusd, repurchaseAmount);
    // wbnb is token0, busd is token1, zeroForOne = false so we are swapping from busd to wbnb
    // amountSpecified is positve since we want to swap exact repurchaseAmount for collat
    // uniV3Pool.swap(address(uniV3FlashLoanRepurchaser), false, repurchaseAmount, 4295128739 + 1, data);
    uniV3FlashLoanRepurchaser.initRepurchase(repurchaseAmount, data, address(uniV3Pool));

    // uint256 snapshot = vm.snapshot();

    // // repurchase 10% of debt
    // uint256 repurchaseAmount = maxBorrowDoge / 10;
    // bytes memory data = abi.encode(USER, SUBACCOUNT_ID, address(doge), address(busd), ibBusd, repurchaseAmount);
    // // have to flashloan repurchaseAmount of doge
    // // doge is token0, busd is token1
    // IPancakePair(0xE27859308ae2424506D1ac7BF5bcb92D6a73e211).swap(
    //   repurchaseAmount,
    //   0,
    //   address(pancakeV2FlashLoanRepurchaser),
    //   data
    // );

    // vm.revertTo(snapshot);

    // // unprofitable case
    // // large account dump pool to make price bad
    // address[] memory swapPath = new address[](2);
    // swapPath[0] = address(busd);
    // swapPath[1] = address(doge);
    // vm.startPrank(0x8894E0a0c962CB723c1976a4421c95949bE2D4E3);
    // busd.approve(address(pancakeRouter), type(uint256).max);
    // pancakeRouter.swapExactTokensForTokens(
    //   1e6 ether,
    //   0,
    //   swapPath,
    //   0x8894E0a0c962CB723c1976a4421c95949bE2D4E3,
    //   block.timestamp
    // );
    // vm.stopPrank();

    // // disable fee
    // vm.mockCall(address(feeModel), abi.encodeWithSelector(FixedFeeModel.getFeeBps.selector), abi.encode(0));
    // // should revert with undeflow so safeTransfer will throw !safeTransfer
    // vm.expectRevert("!safeTransfer");
    // IPancakePair(0xE27859308ae2424506D1ac7BF5bcb92D6a73e211).swap(
    //   repurchaseAmount,
    //   0,
    //   address(pancakeV2FlashLoanRepurchaser),
    //   data
    // );
  }
}
