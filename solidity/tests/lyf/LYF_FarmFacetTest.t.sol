// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LYF_BaseTest, MockERC20, console } from "./LYF_BaseTest.t.sol";

// interfaces
import { ILYFFarmFacet, LibDoublyLinkedList } from "../../contracts/lyf/facets/LYFFarmFacet.sol";
import { IAdminFacet } from "../../contracts/lyf/facets/AdminFacet.sol";

contract LYF_FarmFacetTest is LYF_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    vm.startPrank(ALICE);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserAddFarmPosition_LPShouldBecomeCollateral() external {
    uint256 _borrowAmount = 10 ether;

    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _borrowAmount * 2);
    collateralFacet.addCollateral(BOB, subAccount0, address(usdc), _borrowAmount * 2);

    farmFacet.addFarmPosition(subAccount0, address(wethUsdcLPToken), 10 ether, 10 ether, 0, address(addStrat));
    vm.stopPrank();

    // asset collat of subaccount
    address _bobSubaccount = address(uint160(BOB) ^ uint160(subAccount0));
    uint256 _subAccountWethCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(weth));
    uint256 _subAccountUsdcCollat = collateralFacet.subAccountCollatAmount(_bobSubaccount, address(usdc));

    assertEq(_subAccountWethCollat, 10 ether);
    assertEq(_subAccountUsdcCollat, 10 ether);
  }
}
