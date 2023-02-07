// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";

contract MoneyMarket_Admin_OpenMarketTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenUserOpenNewMarket_ShouldOpenOncePerToken() external {
    MockERC20 _testToken = new MockERC20("test", "TEST", 9);

    // should pass when register new token
    IAdminFacet.TokenConfigInput memory _defaultTokenConfigInput = IAdminFacet.TokenConfigInput({
      token: address(_testToken),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(30 ether, _testToken.decimals()),
      maxCollateral: normalizeEther(100 ether, _testToken.decimals())
    });
    (address _ibToken, ) = adminFacet.openMarket(
      address(_testToken),
      _defaultTokenConfigInput,
      _defaultTokenConfigInput
    );
    assertEq(IERC20(_ibToken).name(), "Interest Bearing TEST");
    assertEq(IERC20(_ibToken).symbol(), "ibTEST");
    assertEq(IERC20(_ibToken).decimals(), 9);

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidToken.selector, address(_testToken)));
    adminFacet.openMarket(address(_testToken), _defaultTokenConfigInput, _defaultTokenConfigInput);

    // able to deposit
    _testToken.mint(ALICE, normalizeEther(5 ether, _testToken.decimals()));
    vm.startPrank(ALICE);
    _testToken.approve(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(address(_testToken), normalizeEther(5 ether, _testToken.decimals()));
    assertEq(IERC20(_ibToken).balanceOf(ALICE), normalizeEther(5 ether, IERC20(_ibToken).decimals()));
  }
}
