// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseRepurchaserForkTest } from "./BaseRepurchaserForkTest.sol";

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
contract PancakeV2FlashLoanRepurchaserForkTest is BaseRepurchaserForkTest {
  PancakeV2FlashLoanRepurchaser internal pancakeV2FlashLoanRepurchaser;

  IPancakeRouter01 internal pancakeRouter = IPancakeRouter01(0x10ED43C718714eb63d5aA57B78B54704E256024E);

  function setUp() public override {
    super.setUp();

    pancakeV2FlashLoanRepurchaser = new PancakeV2FlashLoanRepurchaser(
      address(this),
      address(moneyMarket),
      address(accountManager),
      address(pancakeRouter)
    );
  }

  function testCorrectness_PancakeV2FlashLoanRepurchaser() public {
    // make position
    uint256 collatAmount = 1 ether;

    vm.prank(USER);
    accountManager.depositAndAddCollateral(SUBACCOUNT_ID, address(busd), collatAmount);

    uint256 borrowedAmount = _doMaxBorrow(address(doge), address(busd), collatAmount);

    // mock call
    _mockUnderwaterPrice(address(doge));

    uint256 snapshot = vm.snapshot();

    // repurchase 10% of debt
    uint256 repurchaseAmount = borrowedAmount / 10;

    bytes memory data = abi.encode(
      USER,
      SUBACCOUNT_ID,
      address(doge),
      address(busd),
      moneyMarket.getIbTokenFromToken(address(busd)),
      repurchaseAmount
    );
    // have to flashloan repurchaseAmount of doge
    // doge is token0, busd is token1
    IPancakePair(0xE27859308ae2424506D1ac7BF5bcb92D6a73e211).swap(
      repurchaseAmount,
      0,
      address(pancakeV2FlashLoanRepurchaser),
      data
    );

    vm.revertTo(snapshot);

    // unprofitable case
    // large account dump pool to make price bad
    address[] memory swapPath = new address[](2);
    swapPath[0] = address(busd);
    swapPath[1] = address(doge);
    vm.startPrank(0x8894E0a0c962CB723c1976a4421c95949bE2D4E3);
    busd.approve(address(pancakeRouter), type(uint256).max);
    pancakeRouter.swapExactTokensForTokens(
      1e6 ether,
      0,
      swapPath,
      0x8894E0a0c962CB723c1976a4421c95949bE2D4E3,
      block.timestamp
    );
    vm.stopPrank();

    // disable fee
    vm.mockCall(address(feeModel), abi.encodeWithSelector(FixedFeeModel.getFeeBps.selector), abi.encode(0));
    // should revert with undeflow so safeTransfer will throw !safeTransfer
    vm.expectRevert("!safeTransfer");
    IPancakePair(0xE27859308ae2424506D1ac7BF5bcb92D6a73e211).swap(
      repurchaseAmount,
      0,
      address(pancakeV2FlashLoanRepurchaser),
      data
    );
  }
}
