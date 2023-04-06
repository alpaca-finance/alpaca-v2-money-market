// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BaseRepurchaserForkTest.sol";

import { FlashLoanRepurchaser } from "solidity/contracts/repurchaser/FlashLoanRepurchaser.sol";

import { IPancakeRouter02 } from "solidity/contracts/repurchaser/interfaces/IPancakeRouter02.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// this test is not intended to be ran with normal test suite
// as it requires local fork of bsc mainnet that has money market setup
contract FlashLoanRepurchaserForkTest is BaseRepurchaserForkTest {
  IPancakeRouter02 internal pancakeRouter = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

  FlashLoanRepurchaser internal flashLoanRepurchaser;

  function setUp() public override {
    super.setUp();

    flashLoanRepurchaser = new FlashLoanRepurchaser(address(this), address(moneyMarket), address(accountManager));
  }

  function testCorrectness_PancakeV2SingleHopFlashSwapRepurchaser() public {
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
      repurchaseAmount,
      uint24(0)
    );
    // have to flashloan repurchaseAmount of doge
    flashLoanRepurchaser.pancakeV2SingleHopFlashSwapRepurchase(data);

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
    flashLoanRepurchaser.pancakeV2SingleHopFlashSwapRepurchase(data);
  }

  function testCorrectness_PancakeV3SingleHopFlashSwapRepurchaser() public {
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
      repurchaseAmount,
      uint24(500)
    );

    flashLoanRepurchaser.pancakeV3SingleHopFlashSwapRepurchase(data);
  }
}
