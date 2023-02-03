// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest } from "./LYF_BaseTest.t.sol";

// ---- Interfaces ---- //
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { ILYFLiquidationFacet } from "../../contracts/lyf/interfaces/ILYFLiquidationFacet.sol";

// ---- Mocks ---- //
import { MockLiquidationStrategy } from "../mocks/MockLiquidationStrategy.sol";

contract LYF_Admin_WriteOffDebtTest is LYF_BaseTest {
  event LogWriteOffSubAccountDebt(
    address indexed subAccount,
    address indexed token,
    address indexed lpToken,
    uint256 debtShareWrittenOff,
    uint256 debtValueWrittenOff
  );

  address _collatToken;
  address _debtToken;
  address _lpToken;
  MockLiquidationStrategy internal mockLiquidationStrategy;

  function setUp() public override {
    super.setUp();

    // define tokens
    _collatToken = address(weth);
    _debtToken = address(usdc);
    _lpToken = address(wethUsdcLPToken);

    // setup liquidationStrategy
    mockLiquidationStrategy = new MockLiquidationStrategy(address(mockOracle));
    usdc.mint(address(mockLiquidationStrategy), normalizeEther(1000 ether, usdcDecimal));

    address[] memory _liquidationStrats = new address[](1);
    _liquidationStrats[0] = address(mockLiquidationStrategy);
    adminFacet.setLiquidationStratsOk(_liquidationStrats, true);

    address[] memory _liquidators = new address[](1);
    _liquidators[0] = address(this);
    adminFacet.setLiquidatorsOk(_liquidators, true);

    usdc.approve(lyfDiamond, type(uint256).max);

    // alice add collateral and open positions
    vm.startPrank(ALICE);
    for (uint256 _subAccount = 0; _subAccount < 2; ) {
      uint256 _decrement = _subAccount * 10 ether;

      collateralFacet.addCollateral(ALICE, _subAccount, _collatToken, (40 ether - _decrement));
      ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
        subAccountId: _subAccount,
        lpToken: _lpToken,
        token0: address(weth),
        minLpReceive: 0,
        desiredToken0Amount: (30 ether - _decrement),
        desiredToken1Amount: normalizeEther((30 ether - _decrement), usdcDecimal),
        token0ToBorrow: 0,
        token1ToBorrow: normalizeEther((30 ether - _decrement), usdcDecimal),
        token0AmountIn: 0,
        token1AmountIn: 0
      });
      farmFacet.addFarmPosition(_input);

      unchecked {
        _subAccount++;
      }
    }
    vm.stopPrank();

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, _collatToken), 10 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount0, _lpToken), 30 ether);

    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount1, _collatToken), 10 ether);
    assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, subAccount1, _lpToken), 20 ether);
  }

  function testCorrectness_WhenAdminWriteOffSubAccountsDebt_DebtShouldBeZero() external {
    /**
     * scenario: (subAccount0)
     *
     * 1. @ 1 usdc/weth: alice add collateral 40 weth, open farm with 30 weth, 30 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 30 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 2 * 0.9) = 63 usd
     *      - alice used borrowing power = (30 * 1)/0.9 = 33.333333333333333333 usd
     *    Note: this step is on setUp()
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (30 * 0.5 * 0.9) = 22.5 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 10 USDC
     *      - treasury get 1% of repaid debt = 10 * 1/100 = 0.1
     *      - actual repay = 10 - 0.1 = 9.9 USDC
     *
     * 4. liquidator liquidate 30 lp (all lp)
     *
     * 5. alice position after liquidate
     *      - alice subaccount 0: lp collateral = 30 - 30 = 0 lp
     *      - alice subaccount 0: weth collateral = 10 - 10 = 0 weth
     *      - alice subaccount 0: usdc debt = 30 - 9.9 = 20.1 usdc
     *
     * 6. admin write off alice subaccount to be 0 debt
     *      - alice subaccount 0: usdc debt = 20.1 - 20.1 = 0 usdc
     */

    /**
     * scenario: (subAccount1)
     *
     * 1. @ 1 usdc/weth: alice add collateral 30 weth, open farm with 20 weth, 20 usdc
     *      - 30 weth collateral is used to open position -> 10 weth left as collateral
     *      - alice need to borrow 20 usdc
     *      - alice total borrowing power = (10 * 1 * 0.9) + (20 * 2 * 0.9) = 45 usd
     *      - alice used borrowing power = (20 * 1)/0.9 = 22.222222222222222222 usd
     *    Note: this step is on setUp()
     *
     * 2. lp price drops to 0.5 usdc/lp -> position become repurchaseable
     *      - alice total borrowing power = (10 * 1 * 0.9) + (20 * 0.5 * 0.9) = 18 usd
     *
     * 3. liquidator liquidate alice position
     *      - repay 10 USDC
     *      - treasury get 1% of repaid debt = 10 * 1/100 = 0.1
     *      - actual repay = 10 - 0.1 = 9.9 USDC
     *
     * 4. liquidator liquidate 30 lp (all lp)
     *
     * 5. alice position after liquidate
     *      - alice subaccount 0: lp collateral = 20 - 20 = 0 lp
     *      - alice subaccount 0: weth collateral = 10 - 10 = 0 weth
     *      - alice subaccount 0: usdc debt = 20 - 9.9 = 10.1 usdc
     *
     * 6. admin write off alice subaccount to be 0 debt
     *      - alice subaccount 0: usdc debt = 10.1 - 10.1 = 0 usdc
     */

    // set decreased lpToken price
    mockOracle.setLpTokenPrice(_lpToken, 0.5 ether);

    ILYFAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new ILYFAdminFacet.WriteOffSubAccountDebtInput[](2);

    for (uint256 _i = 0; _i < 2; ) {
      // liquidate alice's position
      uint256 _subAccount = _i;
      uint256 _decrement = _i * 10 ether;

      liquidationFacet.liquidationCall(
        address(mockLiquidationStrategy),
        ALICE,
        _subAccount,
        _debtToken,
        _collatToken,
        _lpToken,
        normalizeEther(10 ether, usdcDecimal),
        0
      );
      liquidationFacet.lpLiquidationCall(ALICE, _subAccount, _lpToken, (30 ether - _decrement), 0, 0);

      assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccount, _collatToken), 0);
      assertEq(viewFacet.getSubAccountTokenCollatAmount(ALICE, _subAccount, _lpToken), 0);

      // get remaining debt
      uint256 _subAccountRemainingDebtValue = normalizeEther((20.1 ether - _decrement), usdcDecimal);
      (, uint256 _subAccountDebtValue) = viewFacet.getSubAccountDebt(ALICE, _subAccount, _debtToken, _lpToken);
      assertEq(_subAccountDebtValue, _subAccountRemainingDebtValue);

      // write off debt
      _inputs[_i] = ILYFAdminFacet.WriteOffSubAccountDebtInput(ALICE, _subAccount, _debtToken, _lpToken);

      vm.expectEmit(true, true, true, true, lyfDiamond);
      emit LogWriteOffSubAccountDebt(
        viewFacet.getSubAccount(ALICE, _subAccount),
        _debtToken,
        _lpToken,
        _subAccountRemainingDebtValue,
        _subAccountRemainingDebtValue
      );

      unchecked {
        _i++;
      }
    }

    adminFacet.writeOffSubAccountsDebt(_inputs);

    (, uint256 subAccount0DebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, _debtToken, _lpToken);
    (, uint256 subAccount1DebtValue) = viewFacet.getSubAccountDebt(ALICE, subAccount0, _debtToken, _lpToken);
    assertEq(subAccount0DebtValue, 0);
    assertEq(subAccount1DebtValue, 0);
  }

  function testRevert_WhenAdminWriteOffSubAccountsDebt_ButOneSubAccountIsHealthy() external {
    // make subAccount0 unhealthy while subAccount1 is still healthy
    mockOracle.setLpTokenPrice(_lpToken, 0.5 ether);

    liquidationFacet.liquidationCall(
      address(mockLiquidationStrategy),
      ALICE,
      subAccount0,
      _debtToken,
      _collatToken,
      _lpToken,
      normalizeEther(10 ether, usdcDecimal),
      0
    );
    liquidationFacet.lpLiquidationCall(ALICE, subAccount0, _lpToken, 30 ether, 0, 0);

    ILYFAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new ILYFAdminFacet.WriteOffSubAccountDebtInput[](2);
    _inputs[0] = ILYFAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount0, _debtToken, _lpToken);
    _inputs[1] = ILYFAdminFacet.WriteOffSubAccountDebtInput(ALICE, subAccount1, _debtToken, _lpToken);

    // should revert since subaccount1 is healthy
    vm.expectRevert(
      abi.encodeWithSelector(
        ILYFAdminFacet.LYFAdminFacet_SubAccountHealthy.selector,
        viewFacet.getSubAccount(ALICE, subAccount1)
      )
    );
    adminFacet.writeOffSubAccountsDebt(_inputs);
  }

  function testRevert_WhenNonAdminWriteOffSubAccountDebt() external {
    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    ILYFAdminFacet.WriteOffSubAccountDebtInput[] memory _inputs = new ILYFAdminFacet.WriteOffSubAccountDebtInput[](1);
    _inputs[0] = ILYFAdminFacet.WriteOffSubAccountDebtInput(
      ALICE,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );
    adminFacet.writeOffSubAccountsDebt(_inputs);
  }
}
