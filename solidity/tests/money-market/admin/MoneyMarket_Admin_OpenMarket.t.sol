// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibConstant } from "../../../contracts/money-market/libraries/LibConstant.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IMiniFL } from "../../../contracts/money-market/interfaces/IMiniFL.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

// mocks
import { MockERC20 } from "../../mocks/MockERC20.sol";

contract MoneyMarket_Admin_OpenMarketTest is MoneyMarket_BaseTest {
  MockERC20 internal _testToken;
  IAdminFacet.TokenConfigInput internal _defaultTokenConfigInput;
  address _ibToken;

  function setUp() public override {
    super.setUp();

    _testToken = new MockERC20("test", "TEST", 9);
    _defaultTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(30 ether, _testToken.decimals()),
      maxCollateral: normalizeEther(100 ether, _testToken.decimals())
    });
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldOpenOncePerToken() external {
    // should pass when register new token
    _ibToken = adminFacet.openMarket(address(_testToken), _defaultTokenConfigInput, _defaultTokenConfigInput);
    assertEq(IERC20(_ibToken).name(), "Interest Bearing TEST");
    assertEq(IERC20(_ibToken).symbol(), "ibTEST");
    assertEq(IERC20(_ibToken).decimals(), 9);

    address _debtToken = viewFacet.getDebtTokenFromToken(address(_testToken));
    assertEq(IERC20(_debtToken).name(), "debtTEST");
    assertEq(IERC20(_debtToken).symbol(), "debtTEST");
    assertEq(IERC20(_debtToken).decimals(), 9);

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidToken.selector, address(_testToken)));
    adminFacet.openMarket(address(_testToken), _defaultTokenConfigInput, _defaultTokenConfigInput);

    // able to deposit
    _testToken.mint(ALICE, normalizeEther(5 ether, _testToken.decimals()));
    vm.startPrank(ALICE);
    _testToken.approve(address(accountManager), type(uint256).max);
    accountManager.deposit(address(_testToken), normalizeEther(5 ether, _testToken.decimals()));
    vm.stopPrank();
    assertEq(IERC20(_ibToken).balanceOf(ALICE), normalizeEther(5 ether, IERC20(_ibToken).decimals()));
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldAddPoolsInMiniFL() external {
    // from setUp() now there are 12 pools with 0 allocPoint
    uint256 _poolLengthBefore = miniFL.poolLength();
    uint256 _allocPointBefore = miniFL.totalAllocPoint();

    // register new token
    _ibToken = adminFacet.openMarket(address(_testToken), _defaultTokenConfigInput, _defaultTokenConfigInput);

    // after openMarket MiniFL should have existed pool + 2 pools
    // 2 added pools (ibToken, debtToken)
    uint256 _poolLengthAfter = miniFL.poolLength();
    uint256 _allocPointAfter = miniFL.totalAllocPoint();
    assertEq(_poolLengthAfter, _poolLengthBefore + 2);
    assertEq(_allocPointAfter, _allocPointBefore);
  }
}
