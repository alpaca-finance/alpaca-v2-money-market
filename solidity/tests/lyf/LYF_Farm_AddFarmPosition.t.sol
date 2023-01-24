// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet } from "../../contracts/lyf/facets/LYFFarmFacet.sol";

contract LYF_Farm_AddFarmPositionTest is LYF_BaseTest {
  function setUp() public override {
    super.setUp();
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
    uint256 _wethBalanceBefore = weth.balanceOf(user);
    uint256 _usdcBalanceBefore = usdc.balanceOf(user);
    uint256 _wethCollatBefore = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(weth));
    uint256 _usdcCollatBefore = viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(usdc));

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
    assertEq(
      viewFacet.getTokenDebtValue(address(weth), address(wethUsdcLPToken)),
      token0ToBorrow,
      string.concat(testcaseName, ": weth debt")
    );
    assertEq(
      viewFacet.getTokenDebtValue(address(usdc), address(wethUsdcLPToken)),
      token1ToBorrow,
      string.concat(testcaseName, ": usdc debt")
    );
    // check wallet
    assertEq(_wethBalanceBefore - weth.balanceOf(user), token0AmountIn, string.concat(testcaseName, ": weth balance"));
    assertEq(_usdcBalanceBefore - usdc.balanceOf(user), token1AmountIn, string.concat(testcaseName, ": usdc balance"));
    // check collat
    assertEq(
      _wethCollatBefore - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(weth)),
      desireToken0Amount - token0ToBorrow - token0AmountIn,
      string.concat(testcaseName, ": weth collat")
    );
    assertEq(
      _usdcCollatBefore - viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(usdc)),
      desireToken1Amount - token1ToBorrow - token1AmountIn,
      string.concat(testcaseName, ": usdc collat")
    );
    assertEq(
      viewFacet.getSubAccountTokenCollatAmount(user, subAccount0, address(wethUsdcLPToken)),
      (desireToken0Amount + desireToken1Amount) / 2, // mockRouter return this
      string.concat(testcaseName, ": lp collat")
    );
  }

  function testCorrectness_WhenAddFarmPosition_ShouldWork() public {
    uint256 snapshot = vm.snapshot();

    // only wallet
    _testAddFarmSuccess("only wallet", ALICE, 1 ether, 1 ether, 0, 0, 1 ether, 1 ether);
    vm.revertTo(snapshot);

    // only debt
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess("only debt", ALICE, 1 ether, 1 ether, 1 ether, 1 ether, 0, 0);
    vm.revertTo(snapshot);

    // only collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("only collat", ALICE, 1 ether, 1 ether, 0, 0, 0, 0);
    vm.revertTo(snapshot);

    // wallet + debt
    snapshot = vm.snapshot();
    vm.prank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 10 ether);
    _testAddFarmSuccess("wallet + debt", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.5 ether, 0.5 ether);
    vm.revertTo(snapshot);

    // wallet + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("wallet + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.5 ether, 0.5 ether);
    vm.revertTo(snapshot);

    // debt + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("debt + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0, 0);
    vm.revertTo(snapshot);

    // wallet + debt + collat
    snapshot = vm.snapshot();
    vm.startPrank(ALICE);
    collateralFacet.addCollateral(ALICE, subAccount0, address(weth), 1 ether);
    collateralFacet.addCollateral(ALICE, subAccount0, address(usdc), 1 ether);
    vm.stopPrank();
    _testAddFarmSuccess("debt + collat", ALICE, 1 ether, 1 ether, 0.5 ether, 0.5 ether, 0.1 ether, 0.1 ether);
    vm.revertTo(snapshot);
  }

  // bad input
  // borrow, wallet, collat
  // min lp receive
  // deposit to masterchef
  // fail mindebtsize
  // fail collatnotenough
  // fail healthcheck (collatFactor, tomuchdebt)
}
