// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";

// interfaces
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";

// contract
import { PancakeswapV2IbTokenLiquidationStrategy } from "../../contracts/money-market/PancakeswapV2IbTokenLiquidationStrategy.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";
import { MockRouter02 } from "../mocks/MockRouter02.sol";

contract LYF_Liquidation_IbLiquidationCallTest is LYF_BaseTest {
  PancakeswapV2IbTokenLiquidationStrategy _ibTokenLiquidationStrat;
  MockRouter02 internal router;

  struct CacheState {
    // general
    uint256 lyfDebtTokenOutStanding;
    // debt
    uint256 debtPoolTotalValue;
    uint256 debtPoolShare;
    uint256 subAccountDebtValue;
    // collat
    uint256 tokenCollatAmount;
    uint256 subAccountCollatAmount;
    // fee
    uint256 treasuryDebtTokenBalance;
    uint256 liquidatorDebtTokenBalance;
  }

  function _getCacheState(
    address _account,
    uint256 _subAccountId,
    address _collatToken,
    address _debtToken,
    address _lpToken
  ) internal view returns (CacheState memory _cachestate) {
    uint256 _debtPoolId = viewFacet.getDebtPoolIdOf(_debtToken, _lpToken);
    uint256 _userDebtTokenValue;
    (, _userDebtTokenValue) = viewFacet.getSubAccountDebt(_account, _subAccountId, address(usdc), _lpToken);

    _cachestate = CacheState({
      lyfDebtTokenOutStanding: viewFacet.getOutstandingBalanceOf(_debtToken),
      debtPoolTotalValue: viewFacet.getDebtPoolTotalValue(_debtPoolId),
      debtPoolShare: viewFacet.getDebtPoolTotalShare(_debtPoolId),
      subAccountDebtValue: _userDebtTokenValue,
      tokenCollatAmount: viewFacet.getTokenCollatAmount(_collatToken),
      subAccountCollatAmount: viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccountId, _collatToken),
      treasuryDebtTokenBalance: usdc.balanceOf(liquidationTreasury),
      liquidatorDebtTokenBalance: usdc.balanceOf(liquidator)
    });
  }

  function setUp() public override {
    super.setUp();

    router = new MockRouter02(address(wethUsdcLPToken), address(mockOracle));
    usdc.mint(address(router), 100 ether); // prepare for swap

    _ibTokenLiquidationStrat = new PancakeswapV2IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarketDiamond)
    );

    // whitelist
    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(_ibTokenLiquidationStrat);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidators = new address[](1);
    _liquidators[0] = address(liquidator);
    adminFacet.setLiquidatorsOk(_liquidators, true);

    address[] memory _liquidationExecutors = new address[](1);
    _liquidationExecutors[0] = address(lyfDiamond);
    _ibTokenLiquidationStrat.setCallersOk(_liquidationExecutors, true);

    address[] memory _btcUsdcPaths = new address[](2);
    _btcUsdcPaths[0] = address(btc);
    _btcUsdcPaths[1] = address(usdc);

    address[] memory _wethUsdcPths = new address[](2);
    _wethUsdcPths[0] = address(weth);
    _wethUsdcPths[1] = address(usdc);

    PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[]
      memory _setPathsInputs = new PancakeswapV2IbTokenLiquidationStrategy.SetPathParams[](2);
    _setPathsInputs[0] = PancakeswapV2IbTokenLiquidationStrategy.SetPathParams({ path: _btcUsdcPaths });
    _setPathsInputs[1] = PancakeswapV2IbTokenLiquidationStrategy.SetPathParams({ path: _wethUsdcPths });

    _ibTokenLiquidationStrat.setPaths(_setPathsInputs);
  }

  function testCorrectness_WhenSubAccountWentUnderWaterWithIbCollat_ShouldBeAbleToPartialLiquidateIbCollat() external {
    /*
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 4 ibBtc, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 weth and 30 usdc
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 2 * 0.9) = 90 usd
     *      - alice used borrowing power = (30 * 1)/0.9 + (30 * 1)/0.9 = 66.666666666666666666 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become liquidatable
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 5 USDC
     *      - treasury get 1% of repaid debt = 5 * 1/100 = 0.05
     *      - actual repay = 5 + 0.05 = 5.05
     *      - BTC price = 10, need to swap 5.05/10 = 0.505 BTC for 5.05 USDC
     *      - ibBtc/Btc Price = 1, need to withdraw  0.505 ibBTC from MM
     *      - actual repay = 5 USDC
     *
     * 4. alice position after liquidate
     *      - alice subaccount 0: ibBtc collateral = 4 - 0.505 = 3.495 ibBtc
     *      - alice subaccount 0: usdc debt = 30 - 5 = 25 usdc
     *      - lyf USDC outstanding should increase by repaid amount = 5 USDC
     */

    address _collatToken = address(ibBtc);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = normalizeEther(5 ether, usdcDecimal);

    vm.startPrank(ALICE);
    btc.approve(moneyMarketDiamond, type(uint256).max);
    IMoneyMarket(moneyMarketDiamond).deposit(address(btc), 4 ether);

    ibBtc.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 4 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 30 ether,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, _collatToken), 4 ether);
    assertEq(viewFacet.getTotalBorrowingPower(ALICE, subAccount0), 90 ether);
    assertEq(viewFacet.getTotalUsedBorrowingPower(ALICE, subAccount0), 66.666666666666666666 ether);

    usdc.mint(liquidator, 10000 ether);

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    CacheState memory _stateBefore = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);

    vm.startPrank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      0
    );
    vm.stopPrank();

    CacheState memory _stateAfter = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);

    // ibBtc collateral is sold to repay
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, address(ibBtc)), 3.495 ether);

    // debt reduce
    assertEq(_stateAfter.subAccountDebtValue, normalizeEther(25 ether, usdcDecimal));

    // LYF outstanding
    assertEq(_stateAfter.lyfDebtTokenOutStanding - _stateBefore.lyfDebtTokenOutStanding, _repayAmount);

    // liquidator get fee
    assertEq(
      _stateAfter.liquidatorDebtTokenBalance - _stateBefore.liquidatorDebtTokenBalance,
      normalizeEther(0.025 ether, usdcDecimal),
      "!fee to liquidator"
    );
    // liquidationTreasury get fee
    assertEq(
      _stateAfter.treasuryDebtTokenBalance - _stateBefore.treasuryDebtTokenBalance,
      normalizeEther(0.025 ether, usdcDecimal),
      "!fee to treasury"
    );
  }

  function testCorrectness_WhenLiquidateIbTokenCollatIsLessThanRequire_DebtShouldRepayAndCollatShouldBeGone() external {
    /*
     * scenario:
     *
     * 1. @ 1 usdc/weth: alice add collateral 20 ibWeth, open farm with 30 weth, 30 usdc
     *      - alice need to borrow 30 weth and 30 usdc
     *      - alice total borrowing power = (20 * 1 * 0.9) + (30 * 2 * 0.9) = 72 usd
     *      - alice used borrowing power = (30 * 1)/0.9 + (30 * 1)/0.9 = 66.666666666666666666 usd
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become liquidatable
     *      - alice total borrowing power = (4 * 10 * 0.9) + (30 * 0.5 * 0.9) = 49.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - liquidator wants to repay 30 USDC, but only 20 ibWeth remains as collat
     *      - withdraw 20 weth and swap to 20 USDC
     *      - actualLiquidationFee = 20 * 0.3 / 30.3 = 0.198019
     *      - actualRepay = 20 - 0.198019 = 19.801981
     *
     * 4. alice position after liquidate
     *      - alice subaccount 0: ibWeth collateral = 0 ibWeth
     *      - alice subaccount 0: usdc debt = 30 - 19.801981 = 10.198019 usdc
     *      - lyf USDC outstanding should increase by repaid amount = 10.198019 USDC
     * 5. Fee
     *      - totalFee = 0.198019
     *      - 50% goes to liquidator = 0.198019 * 5000 / 10000 = 0.099009
     *      - treasury get = 0.198019 - 0.099009 = 0.099010
     */

    // criteria
    address _collatToken = address(ibWeth);
    address _debtToken = address(usdc);
    address _lpToken = address(wethUsdcLPToken);
    uint256 _repayAmount = normalizeEther(30 ether, usdcDecimal);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    IMoneyMarket(moneyMarketDiamond).deposit(address(weth), 20 ether);

    ibBtc.approve(lyfDiamond, type(uint256).max);
    collateralFacet.addCollateral(ALICE, subAccount0, _collatToken, 20 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: _lpToken,
      minLpReceive: 0,
      desiredToken0Amount: 30 ether,
      desiredToken1Amount: normalizeEther(30 ether, usdcDecimal),
      token0ToBorrow: 30 ether,
      token1ToBorrow: normalizeEther(30 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    vm.stopPrank();

    mockOracle.setLpTokenPrice(address(_lpToken), 0.5 ether);

    CacheState memory _stateBefore = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);

    vm.startPrank(liquidator);
    liquidationFacet.liquidationCall(
      address(_ibTokenLiquidationStrat),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      _repayAmount,
      0
    );
    vm.stopPrank();

    CacheState memory _stateAfter = _getCacheState(ALICE, subAccount0, _collatToken, _debtToken, _lpToken);

    // ibBtc collateral is sold to repay
    assertEq(_stateAfter.subAccountCollatAmount, 0 ether);

    // debt reduce
    assertEq(_stateAfter.subAccountDebtValue, 10198019);

    // LYF outstanding
    assertEq(_stateAfter.lyfDebtTokenOutStanding - _stateBefore.lyfDebtTokenOutStanding, 19801981);

    //  liquidator get fee
    assertEq(_stateAfter.liquidatorDebtTokenBalance - _stateBefore.liquidatorDebtTokenBalance, 99009);
    // // treasury get fee
    assertEq(_stateAfter.treasuryDebtTokenBalance - _stateBefore.treasuryDebtTokenBalance, 99010);
  }
}
