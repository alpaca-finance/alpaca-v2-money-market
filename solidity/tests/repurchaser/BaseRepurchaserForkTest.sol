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

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
abstract contract BaseRepurchaserForkTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  FixedFeeModel internal feeModel;

  // update these addresses once you deploy new fork
  IMoneyMarket internal moneyMarket = IMoneyMarket(0x212BbbC23981b7Ae7B9B23aa1356d723d647Ce53);
  IMoneyMarketAccountManager internal accountManager =
    IMoneyMarketAccountManager(0x6e1a13224D759Ef6008da51848C114800E5C4a1b);
  IAlpacaV2Oracle internal oracle = IAlpacaV2Oracle(0xd41cA0E6C44fACBf30c97CD99aeC2Fa4FdCe7a3C);

  address internal DEPLOYER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal USER = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  uint256 internal SUBACCOUNT_ID = 255; // to not collide with existing subAccount setup from script

  IERC20 internal wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 internal busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
  IERC20 internal doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);

  function setUp() public virtual {
    vm.startPrank(DEPLOYER);

    moneyMarket.setMinDebtSize(0);

    // can liquidate up to 50% of used borrowing power
    moneyMarket.setLiquidationParams(5000, 11000);

    feeModel = new FixedFeeModel();
    moneyMarket.setRepurchaseRewardModel(feeModel);

    moneyMarket.setLiquidationTreasury(address(this));

    // seed money market
    accountManager.deposit(address(wbnb), 100 ether);
    accountManager.deposit(address(busd), 100 ether);
    accountManager.deposit(address(doge), 100e8);

    vm.stopPrank();
  }

  function _doMaxBorrow(
    address debtToken,
    address underlyingOfCollatToken,
    uint256 underlyingOfCollatAmount
  ) internal returns (uint256 borrowedAmount) {
    // get price from oracle
    (uint256 debtTokenPrice, ) = oracle.getTokenPrice(debtToken);
    (uint256 underlyingOfCollatTokenPrice, ) = oracle.getTokenPrice(underlyingOfCollatToken);

    // calculate how much debtToken can we max borrow with underlyingOfCollatAmount
    LibConstant.TokenConfig memory debtTokenConfig = moneyMarket.getTokenConfig(address(debtToken));
    address ibCollatToken = moneyMarket.getIbTokenFromToken(address(underlyingOfCollatToken));
    LibConstant.TokenConfig memory ibCollatTokenTokenConfig = moneyMarket.getTokenConfig(ibCollatToken);

    uint256 riskAdjustedUnderlyingOfCollatTokenPrice = (underlyingOfCollatTokenPrice *
      ibCollatTokenTokenConfig.collateralFactor) / LibConstant.MAX_BPS;
    uint256 riskAdjustedDebtTokenPrice = (debtTokenPrice * LibConstant.MAX_BPS) / debtTokenConfig.borrowingFactor;

    uint256 maxBorrowDebt = (underlyingOfCollatAmount * riskAdjustedUnderlyingOfCollatTokenPrice) /
      riskAdjustedDebtTokenPrice /
      (10**(18 - IERC20(debtToken).decimals()));

    vm.prank(USER);
    accountManager.borrow(SUBACCOUNT_ID, debtToken, maxBorrowDebt);

    return maxBorrowDebt;
  }

  function _mockUnderwaterPrice(address token) internal {
    // mockCall price at oracle to make position underwater
    // note that price on dex is not affected
    (uint256 tokenPrice, ) = oracle.getTokenPrice(token);
    uint256 newPrice = (tokenPrice * 10001) / 10000;
    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(IAlpacaV2Oracle.getTokenPrice.selector, token),
      abi.encode(newPrice, block.timestamp)
    );
  }
}
