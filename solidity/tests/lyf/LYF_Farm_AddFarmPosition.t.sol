// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/interfaces/ILYFFarmFacet.sol";
import { ILYFAdminFacet } from "../../contracts/lyf/interfaces/ILYFAdminFacet.sol";
import { IMoneyMarket } from "../../contracts/lyf/interfaces/IMoneyMarket.sol";

// libraries
import { LibLYF01 } from "../../contracts/lyf/libraries/LibLYF01.sol";
import { LibFullMath } from "../../contracts/lyf/libraries/LibFullMath.sol";

contract LYF_Farm_AddFarmPositionTest is LYF_BaseTest {
  IMoneyMarket internal moneyMarket;

  function setUp() public override {
    super.setUp();

    moneyMarket = IMoneyMarket(moneyMarketDiamond);
  }

  struct TestAddFarmSuccessState {
    uint256 wethBalance;
    uint256 wethCollat;
    uint256 wethDebtAmount;
    uint256 usdcBalance;
    uint256 usdcCollat;
    uint256 usdcDebtAmount;
    uint256 lpCollat;
    uint256 ibWethCollat;
  }

  function _testAddFarmSuccess(
    string memory testcaseName,
    address user,
    uint256 desiredToken0Amount,
    uint256 desiredToken1Amount,
    uint256 token0ToBorrow,
    uint256 token1ToBorrow,
    uint256 token0AmountIn,
    uint256 token1AmountIn
  ) internal {
    TestAddFarmSuccessState memory stateBefore;
    stateBefore.wethBalance = weth.balanceOf(user);
    stateBefore.usdcBalance = usdc.balanceOf(user);
    stateBefore.wethCollat = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(weth));
    stateBefore.usdcCollat = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(usdc));
    stateBefore.lpCollat = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(wethUsdcLPToken));
    stateBefore.ibWethCollat = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(ibWeth));

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: desiredToken0Amount,
      desiredToken1Amount: desiredToken1Amount,
      token0ToBorrow: token0ToBorrow,
      token1ToBorrow: token1ToBorrow,
      token0AmountIn: token0AmountIn,
      token1AmountIn: token1AmountIn
    });

    vm.prank(user);
    farmFacet.addFarmPosition(_input);

    // check debt
    (, stateBefore.wethDebtAmount) = viewFacet.getSubAccountDebt(
      user,
      subAccount0,
      address(weth),
      address(wethUsdcLPToken)
    );
    (, stateBefore.usdcDebtAmount) = viewFacet.getSubAccountDebt(
      user,
      subAccount0,
      address(usdc),
      address(wethUsdcLPToken)
    );
    assertEq(stateBefore.wethDebtAmount, token0ToBorrow, string.concat(testcaseName, ": weth debt"));
    assertEq(stateBefore.usdcDebtAmount, token1ToBorrow, string.concat(testcaseName, ": usdc debt"));

    // check wallet
    assertEq(
      stateBefore.wethBalance - weth.balanceOf(user),
      token0AmountIn,
      string.concat(testcaseName, ": weth balance")
    );
    assertEq(
      stateBefore.usdcBalance - usdc.balanceOf(user),
      token1AmountIn,
      string.concat(testcaseName, ": usdc balance")
    );

    // check collat
    uint256 _wethToRemove = desiredToken0Amount - token0ToBorrow - token0AmountIn;
    uint256 _actualWethRemoved = LibFullMath.min(_wethToRemove, stateBefore.wethCollat);
    assertEq(
      stateBefore.wethCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(weth)),
      _actualWethRemoved,
      string.concat(testcaseName, ": weth collat")
    );
    assertEq(
      stateBefore.usdcCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(usdc)),
      desiredToken1Amount - token1ToBorrow - token1AmountIn,
      string.concat(testcaseName, ": usdc collat")
    );
    assertEq(
      stateBefore.ibWethCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(ibWeth)),
      _wethToRemove - _actualWethRemoved,
      string.concat(testcaseName, ": ibWeth collat")
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(wethUsdcLPToken)) - stateBefore.lpCollat,
      (desiredToken0Amount + desiredToken1Amount * 10**(18 - usdcDecimal)) / 2, // mockRouter return this
      string.concat(testcaseName, ": lp collat")
    );
  }

  function testCorrectness_WhenAddFarmPosition_ShouldWork() public {
    uint256 snapshot = vm.snapshot();

    // only wallet
    _testAddFarmSuccess(
      "only wallet",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0,
      0,
      1 ether,
      normalizeEther(1 ether, usdcDecimal)
    );
    vm.revertTo(snapshot);

    // only borrow
    // TODO: remove unnecessary snapshot
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess(
      "only borrow",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0,
      0
    );
    vm.revertTo(snapshot);

    // only normal collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));
    vm.stopPrank();
    _testAddFarmSuccess("only normal collat", ALICE, 1 ether, normalizeEther(1 ether, usdcDecimal), 0, 0, 0, 0);
    vm.revertTo(snapshot);

    // ib collat + wallet
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    moneyMarket.deposit(ALICE, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess(
      "ib collat + wallet",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0,
      normalizeEther(1 ether, usdcDecimal),
      0,
      0
    );
    vm.revertTo(snapshot);

    // normal + ib collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.5 ether);
    moneyMarket.deposit(ALICE, address(weth), 0.5 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.stopPrank();
    _testAddFarmSuccess(
      "normal + ib collat",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0,
      0,
      0,
      normalizeEther(1 ether, usdcDecimal)
    );
    vm.revertTo(snapshot);

    // wallet + borrow
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess(
      "wallet + borrow",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal)
    );
    vm.revertTo(snapshot);

    // wallet + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));
    vm.stopPrank();
    _testAddFarmSuccess(
      "wallet + collat",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal)
    );
    vm.revertTo(snapshot);

    // borrow + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));
    vm.stopPrank();
    _testAddFarmSuccess(
      "borrow + collat",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal),
      0,
      0
    );
    vm.revertTo(snapshot);

    // wallet + borrow + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), normalizeEther(1 ether, usdcDecimal));
    vm.stopPrank();
    _testAddFarmSuccess(
      "wallet + borrow + collat",
      ALICE,
      1 ether,
      normalizeEther(1 ether, usdcDecimal),
      0.5 ether,
      normalizeEther(0.5 ether, usdcDecimal),
      0.1 ether,
      normalizeEther(0.1 ether, usdcDecimal)
    );
    vm.revertTo(snapshot);
  }

  function testCorrectness_WhenAddFarmPosition_ShouldDepositLPToMasterChef() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: normalizeEther(1 ether, usdcDecimal),
      token0ToBorrow: 0,
      token1ToBorrow: 0,
      token0AmountIn: 1 ether,
      token1AmountIn: normalizeEther(1 ether, usdcDecimal)
    });

    vm.prank(ALICE);
    farmFacet.addFarmPosition(_input);

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));
    (uint256 _depositedLP, ) = masterChef.userInfo(_lpConfig.poolId, lyfDiamond);
    assertEq(_depositedLP, 1 ether);
  }

  function testRevert_WhenAddFarmPositionWithBadInput() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1,
      desiredToken1Amount: 0,
      token0ToBorrow: 1,
      token1ToBorrow: 0,
      token0AmountIn: 1,
      token1AmountIn: 0
    });

    vm.prank(ALICE);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BadInput.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionNotEnoughCollat_ShouldFailCollatAmountCheck() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: 0,
      token0ToBorrow: 0,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);

    // no collat
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.addFarmPosition(_input);

    // only normal collat but not enough
    uint256 snapshot = vm.snapshot();
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.addFarmPosition(_input);
    vm.revertTo(snapshot);

    // only ib collat but not enough
    snapshot = vm.snapshot();
    moneyMarket.deposit(ALICE, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.addFarmPosition(_input);
    vm.revertTo(snapshot);

    // not enough normal and ib collat
    snapshot = vm.snapshot();
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.4 ether);
    moneyMarket.deposit(ALICE, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.addFarmPosition(_input);
    vm.revertTo(snapshot);

    // enough collat for token0 but not for token1
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _input.desiredToken1Amount = 1 ether;
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionBorrowLessThanMinDebtSize_ShouldFailMinDebtSizeCheck() public {
    adminFacet.setMinDebtSize(0.5 ether);
    mockOracle.setTokenPrice(address(weth), 1 ether);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: 0,
      token0ToBorrow: 0.4 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.prank(ALICE);
    // minDebtSize 0.5 USD, borrow weth value 0.4 USD
    vm.expectRevert(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionBorrowingPowerDecrease_ShouldFailHealthCheck() public {
    // omit usdc in this test for brevity
    mockOracle.setTokenPrice(address(weth), 1 ether);
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 2 ether);

    ILYFAdminFacet.TokenConfigInput[] memory _tokenConfigInputs = new ILYFAdminFacet.TokenConfigInput[](2);
    _tokenConfigInputs[0] = ILYFAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibLYF01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxCollateral: 100 ether
    });
    _tokenConfigInputs[1] = ILYFAdminFacet.TokenConfigInput({
      token: address(wethUsdcLPToken),
      tier: LibLYF01.AssetTier.LP,
      collateralFactor: 8000,
      borrowingFactor: 1,
      maxCollateral: 100 ether
    });
    adminFacet.setTokenConfigs(_tokenConfigInputs);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: 0,
      token0ToBorrow: 1 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.35 ether);
    // create debt
    farmFacet.addFarmPosition(_input);

    _input.desiredToken0Amount = 0.35 ether;
    _input.token0ToBorrow = 0;
    // borrowing power = amount * collatFactor * price
    // total borrowing power before = weth + lp = 0.35 * 0.9 * 1 + 0.5 * 0.8 * 2 = 1.115 USD
    // total borrowing power after = lp = 0.675 * 0.8 * 2 = 1.08 USD
    // used borrowing power = amount / borrowingFactor * price = 1 / 0.9 * 1 = 1.111.. USD
    // borrowing power after < used borrowing power should revert
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionUsedBorrowingPowerIncrease_ShouldFailHealthCheck() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: 0,
      token0ToBorrow: 1 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.2 ether);

    // borrow only
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.addFarmPosition(_input);

    // borrow + collat
    _input.token0ToBorrow = 0.9 ether;
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testCorrectness_WhenAddFarmPosition_ShouldBorrowMMIfReserveNotEnough() public {
    // omit usdc in this test for brevity
    // create leftover reserve by borrow from mm and repay so tokens is left in lyf
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(btc), 10 ether);
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 10 ether,
      desiredToken1Amount: 0,
      token0ToBorrow: 10 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);
    farmFacet.repay(ALICE, subAccount0, address(weth), address(wethUsdcLPToken), 10 ether);

    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 10 ether);

    // next addFarmPosition should use reserve instead of borrowing from mm
    _input.desiredToken0Amount = 6 ether;
    _input.token0ToBorrow = 6 ether;
    farmFacet.addFarmPosition(_input);
    // 6 ether should be borrowed from reserve so 4 left
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 4 ether);

    // next addFarmPosition should not use reserve but borrow more from mm
    // because desiredAmount > reserve
    uint256 _mmDebtBefore = viewFacet.getMMDebt(address(weth));
    farmFacet.addFarmPosition(_input);
    assertEq(viewFacet.getOutstandingBalanceOf(address(weth)), 4 ether);
    assertEq(viewFacet.getMMDebt(address(weth)) - _mmDebtBefore, 6 ether);
  }

  function testRevert_WhenUserBorrowMoreThanMaxNumOfDebtPerSubAccount() public {
    // allow to borrow only 1 token
    adminFacet.setMaxNumOfToken(10, 1);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), 2 ether);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: 1 ether,
      desiredToken1Amount: normalizeEther(1 ether, usdcDecimal),
      token0ToBorrow: 1 ether,
      token1ToBorrow: normalizeEther(1 ether, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    // revert because try to borrow 2 tokens
    vm.expectRevert(LibLYF01.LibLYF01_NumberOfTokenExceedLimit.selector);
    farmFacet.addFarmPosition(_input);
  }

  function testCorrectness_WhenRepayAndBorrowMoreWithTotalBorrowEqualMaxNumOfDebtPerSubAccount_ShouldWork() external {
    uint256 _wethToAddLP = 30 ether;
    uint256 _usdcToAddLP = 30 ether;
    uint256 _btcToAddLP = 3 ether;
    uint256 _wethCollatAmount = 20 ether;
    uint256 _usdcCollatAmount = 20 ether;

    // allow to borrow 2 tokens
    adminFacet.setMaxNumOfToken(10, 2);

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), normalizeEther(_usdcCollatAmount, usdcDecimal));

    // borrow weth and usdc
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      token0: wethUsdcLPToken.token0(),
      minLpReceive: 0,
      desiredToken0Amount: _wethToAddLP,
      desiredToken1Amount: normalizeEther(_usdcToAddLP, usdcDecimal),
      token0ToBorrow: _wethToAddLP,
      token1ToBorrow: normalizeEther(_usdcToAddLP, usdcDecimal),
      token0AmountIn: 0,
      token1AmountIn: 0
    });
    farmFacet.addFarmPosition(_input);

    // repay all debt
    farmFacet.repay(BOB, subAccount0, address(weth), address(wethUsdcLPToken), type(uint256).max);
    farmFacet.repay(BOB, subAccount0, address(usdc), address(wethUsdcLPToken), type(uint256).max);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethCollatAmount * 2);

    // borrow btc and usdc
    _input.lpToken = address(btcUsdcLPToken);
    _input.token0 = btcUsdcLPToken.token0();
    _input.desiredToken0Amount = _btcToAddLP;
    _input.desiredToken1Amount = normalizeEther(_usdcToAddLP, usdcDecimal);
    _input.token0ToBorrow = _btcToAddLP;
    _input.token1ToBorrow = normalizeEther(_usdcToAddLP, usdcDecimal);
    farmFacet.addFarmPosition(_input);
  }
}
