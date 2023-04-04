// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BaseRepurchaserForkTest.sol";

import { PancakeV3FlashLoanRepurchaser } from "solidity/contracts/repurchaser/PancakeV3FlashLoanRepurchaser.sol";

import { IUniswapV3Pool } from "solidity/contracts/repurchaser/interfaces/IUniswapV3Pool.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
contract PancakeV3FlashLoanRepurchaserForkTest is BaseRepurchaserForkTest {
  PancakeV3FlashLoanRepurchaser internal pcsV3FlashLoanRepurchaser;

  function setUp() public override {
    super.setUp();

    pcsV3FlashLoanRepurchaser = new PancakeV3FlashLoanRepurchaser(
      address(this),
      address(moneyMarket),
      address(accountManager)
    );
  }

  function testCorrectness_PancakeV3FlashLoanRepurchaser() public {
    // make position
    uint256 collatAmount = 1 ether;

    vm.prank(USER);
    accountManager.depositAndAddCollateral(SUBACCOUNT_ID, address(busd), collatAmount);

    uint256 borrowedAmount = _doMaxBorrow(address(wbnb), address(busd), collatAmount);

    // mock call
    _mockUnderwaterPrice(address(wbnb));

    // repurchase 10% of debt
    uint256 repurchaseAmount = borrowedAmount / 10;

    bytes memory data = abi.encode(
      USER,
      SUBACCOUNT_ID,
      address(wbnb),
      address(busd),
      moneyMarket.getIbTokenFromToken(address(busd)),
      uint24(500),
      repurchaseAmount
    );

    pcsV3FlashLoanRepurchaser.initRepurchase(data);
  }
}
