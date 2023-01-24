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
    uint256 desireToken0Amount,
    uint256 desireToken1Amount,
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
      minLpReceive: 0,
      desireToken0Amount: desireToken0Amount,
      desireToken1Amount: desireToken1Amount,
      token0ToBorrow: token0ToBorrow,
      token1ToBorrow: token1ToBorrow,
      token0AmountIn: token0AmountIn,
      token1AmountIn: token1AmountIn
    });

    vm.prank(user);
    farmFacet.newAddFarmPosition(_input);

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
    uint256 _wethToRemove = desireToken0Amount - token0ToBorrow - token0AmountIn;
    uint256 _actualWethRemoved = LibFullMath.min(_wethToRemove, stateBefore.wethCollat);
    assertEq(
      stateBefore.wethCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(weth)),
      _actualWethRemoved,
      string.concat(testcaseName, ": weth collat")
    );
    assertEq(
      stateBefore.usdcCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(usdc)),
      desireToken1Amount - token1ToBorrow - token1AmountIn,
      string.concat(testcaseName, ": usdc collat")
    );
    assertEq(
      stateBefore.ibWethCollat - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(ibWeth)),
      _wethToRemove - _actualWethRemoved,
      string.concat(testcaseName, ": ibWeth collat")
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(wethUsdcLPToken)) - stateBefore.lpCollat,
      (desireToken0Amount + desireToken1Amount) / 2, // mockRouter return this
      string.concat(testcaseName, ": lp collat")
    );
  }

  function testCorrectness_WhenAddFarmPosition_ShouldWork() public {
    uint256 snapshot = vm.snapshot();

    // only wallet
    _testAddFarmSuccess("only wallet", ALICE, 1 ether, 1 ether, 0, 0, 1 ether, 1 ether);
    vm.revertTo(snapshot);

    // only borrow
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess("only borrow", ALICE, 1 ether, 1 ether, 1 ether, 1 ether, 0, 0);
    vm.revertTo(snapshot);

    // only normal collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("only normal collat", ALICE, 1 ether, 1 ether, 0, 0, 0, 0);
    vm.revertTo(snapshot);

    // only ib collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    moneyMarket.deposit(address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("only ib collat", ALICE, 1 ether, 0, 0, 0, 0, 0);
    vm.revertTo(snapshot);

    // normal + ib collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.5 ether);
    moneyMarket.deposit(address(weth), 0.5 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.stopPrank();
    _testAddFarmSuccess("normal + ib collat", ALICE, 1 ether, 0, 0, 0, 0, 0);
    vm.revertTo(snapshot);

    // wallet + borrow
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess("wallet + borrow", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.5 ether, 0.5 ether);
    vm.revertTo(snapshot);

    // wallet + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("wallet + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.5 ether, 0.5 ether);
    vm.revertTo(snapshot);

    // borrow + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("borrow + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0, 0);
    vm.revertTo(snapshot);

    // wallet + borrow + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("borrow + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.1 ether, 0.1 ether);
    vm.revertTo(snapshot);
  }

  function testCorrectness_WhenAddFarmPosition_ShouldDepositLPToMasterChef() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1 ether,
      desireToken1Amount: 1 ether,
      token0ToBorrow: 0,
      token1ToBorrow: 0,
      token0AmountIn: 1 ether,
      token1AmountIn: 1 ether
    });

    vm.prank(ALICE);
    farmFacet.newAddFarmPosition(_input);

    LibLYF01.LPConfig memory _lpConfig = viewFacet.getLpTokenConfig(address(wethUsdcLPToken));
    (uint256 _depositedLP, ) = masterChef.userInfo(_lpConfig.poolId, lyfDiamond);
    assertEq(_depositedLP, 1 ether);
  }

  function testRevert_WhenAddFarmPositionWithBadInput() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1,
      desireToken1Amount: 0,
      token0ToBorrow: 1,
      token1ToBorrow: 0,
      token0AmountIn: 1,
      token1AmountIn: 0
    });

    vm.prank(ALICE);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BadInput.selector);
    farmFacet.newAddFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionNotEnoughCollat_ShouldFailCollatAmountCheck() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1 ether,
      desireToken1Amount: 0,
      token0ToBorrow: 0,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);

    // no collat
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.newAddFarmPosition(_input);

    // only normal collat but not enough
    uint256 snapshot = vm.snapshot();
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.newAddFarmPosition(_input);
    vm.revertTo(snapshot);

    // only ib collat but not enough
    snapshot = vm.snapshot();
    moneyMarket.deposit(address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.newAddFarmPosition(_input);
    vm.revertTo(snapshot);

    // not enough normal and ib collat
    snapshot = vm.snapshot();
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.4 ether);
    moneyMarket.deposit(address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(ibWeth), 0.5 ether);
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.newAddFarmPosition(_input);
    vm.revertTo(snapshot);

    // enough collat for token0 but not for token1
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _input.desireToken1Amount = 1 ether;
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_CollatNotEnough.selector);
    farmFacet.newAddFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionBorrowLessThanMinDebtSize_ShouldFailMinDebtSizeCheck() public {
    adminFacet.setMinDebtSize(0.5 ether);
    mockOracle.setTokenPrice(address(weth), 1 ether);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1 ether,
      desireToken1Amount: 0,
      token0ToBorrow: 0.4 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.prank(ALICE);
    // minDebtSize 0.5 USD, borrow weth value 0.4 USD
    vm.expectRevert(LibLYF01.LibLYF01_BorrowLessThanMinDebtSize.selector);
    farmFacet.newAddFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionBorrowingPowerDecrease_ShouldFailHealthCheck() public {
    // omit usdc in test for brevity
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
      borrowingFactor: 0,
      maxCollateral: 100 ether
    });
    adminFacet.setTokenConfigs(_tokenConfigInputs);

    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1 ether,
      desireToken1Amount: 0,
      token0ToBorrow: 1 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.35 ether);
    // create debt
    farmFacet.newAddFarmPosition(_input);

    _input.desireToken0Amount = 0.35 ether;
    _input.token0ToBorrow = 0;
    // borrowing power = amount * collatFactor * price
    // total borrowing power before = weth + lp = 0.35 * 0.9 * 1 + 0.5 * 0.8 * 2 = 1.115 USD
    // total borrowing power after = lp = 0.675 * 0.8 * 2 = 1.08 USD
    // used borrowing power = amount / borrowingFactor * price = 1 / 0.9 * 1 = 1.111.. USD
    // borrowing power after < used borrowing power should revert
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.newAddFarmPosition(_input);
  }

  function testRevert_WhenAddFarmPositionUsedBorrowingPowerIncrease_ShouldFailHealthCheck() public {
    ILYFFarmFacet.AddFarmPositionInput memory _input = ILYFFarmFacet.AddFarmPositionInput({
      subAccountId: subAccount0,
      lpToken: address(wethUsdcLPToken),
      minLpReceive: 0,
      desireToken0Amount: 1 ether,
      desireToken1Amount: 0,
      token0ToBorrow: 1 ether,
      token1ToBorrow: 0,
      token0AmountIn: 0,
      token1AmountIn: 0
    });

    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 0.2 ether);

    // borrow only
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.newAddFarmPosition(_input);

    // borrow + collat
    _input.token0ToBorrow = 0.9 ether;
    vm.expectRevert(ILYFFarmFacet.LYFFarmFacet_BorrowingPowerTooLow.selector);
    farmFacet.newAddFarmPosition(_input);
  }

  //   function testCorrectness_WhenAddFarmPosition_ShouldBorrowMMIfReserveNotEnough() public {

  //   }
}
