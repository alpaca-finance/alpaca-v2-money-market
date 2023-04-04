// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseRepurchaserForkTest } from "./BaseRepurchaserForkTest.sol";

import { UniswapV3FlashloanRepurchaser } from "solidity/contracts/repurchaser/UniswapV3FlashloanRepurchaser.sol";

import { IUniswapV3Pool } from "solidity/contracts/repurchaser/interfaces/IUniswapV3Pool.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
contract UniswapV3FlashLoanRepurchaserForkTest is BaseRepurchaserForkTest {
  UniswapV3FlashloanRepurchaser internal uniV3FlashLoanRepurchaser;
  // WBNB-BUSD pool
  IUniswapV3Pool internal uniV3Pool = IUniswapV3Pool(0x32776Ed4D96ED069a2d812773F0AD8aD9Ef83CF8);

  function setUp() public override {
    super.setUp();

    uniV3FlashLoanRepurchaser = new UniswapV3FlashloanRepurchaser(
      address(this),
      address(moneyMarket),
      address(accountManager)
    );
  }

  function testCorrectness_UniswapV3FlashLoanRepurchaser() public {
    // make position
    uint256 collatAmount = 1 ether;

    vm.prank(USER);
    accountManager.depositAndAddCollateral(SUBACCOUNT_ID, address(busd), collatAmount);

    uint256 borrowedAmount = _doMaxBorrow(address(wbnb), address(busd), collatAmount);

    // mock call
    _mockUnderwaterPrice(address(wbnb));

    // repurchase 10% of debt
    uint256 repurchaseAmount = borrowedAmount / 10;

    uniV3FlashLoanRepurchaser.initRepurchase(
      USER,
      SUBACCOUNT_ID,
      address(wbnb),
      address(busd),
      moneyMarket.getIbTokenFromToken(address(busd)),
      repurchaseAmount,
      address(uniV3Pool)
    );
  }
}
