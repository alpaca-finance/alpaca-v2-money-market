// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";

// libraries
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";

// helpers
import { TestHelper } from "../helper/TestHelper.sol";

contract MoneyMarket_To18ConversionFactorTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenMMConvert18DecimalPlacesToken_ShouldHandleDecimalConversionFactorCorrectly() external {
    // openMarket 18 decimals
    address _token18 = address(new MockERC20("18 decimals", "18", 18));
    address _ibToken18 = address(TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(_token18)));
    assertEq(IERC20(_ibToken18).decimals(), 18);
    assertEq(viewFacet.getTokenConfig(_token18).to18ConversionFactor, 1);

    // setTokenConfigs 18 decimals
    address[] memory _tokens = new address[](1);
    _tokens[0] = _token18;

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });

    adminFacet.setTokenConfigs(_tokens, _inputs);
    assertEq(viewFacet.getTokenConfig(_token18).to18ConversionFactor, 1);
  }

  function testCorrectness_WhenMMConvertTokensWithDecimalPlacesLessThan18_ShouldHandleDecimalConversionFactorCorrectly()
    external
  {
    // openMarket 12 decimals
    address _token12 = address(new MockERC20("12 decimals", "12", 12));
    address _ibToken12 = address(TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(_token12)));
    assertEq(IERC20(_ibToken12).decimals(), 12);
    assertEq(viewFacet.getTokenConfig(_token12).to18ConversionFactor, 10**6);

    // setTokenConfigs 12 decimals
    address[] memory _tokens = new address[](1);
    _tokens[0] = _token12;

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });

    adminFacet.setTokenConfigs(_tokens, _inputs);
    assertEq(viewFacet.getTokenConfig(_token12).to18ConversionFactor, 10**6);

    // openMarket 1 decimals
    address _token1 = address(new MockERC20("1 decimals", "1", 1));
    address _ibToken1 = address(TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(_token1)));
    assertEq(IERC20(_ibToken1).decimals(), 1);
    assertEq(viewFacet.getTokenConfig(_token1).to18ConversionFactor, 10**17);

    // setTokenConfigs 1 decimals
    _tokens[0] = _token1;
    // reuse `_inputs`

    adminFacet.setTokenConfigs(_tokens, _inputs);
    assertEq(viewFacet.getTokenConfig(_token1).to18ConversionFactor, 10**17);
  }

  function testRevert_WhenMMConvertTokenWithDecimalPlacesGreaterThan18() external {
    // openMarket 19 decimals
    address _token19 = address(new MockERC20("19 decimals", "19", 19));
    IAdminFacet.TokenConfigInput memory _tokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1,
      maxCollateral: 1
    });
    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_UnsupportedDecimals.selector);
    adminFacet.openMarket(_token19, _tokenConfigInput, _tokenConfigInput);

    // setTokenConfigs 19 decimals
    address[] memory _tokens = new address[](1);
    _tokens[0] = _token19;

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });

    vm.expectRevert(LibMoneyMarket01.LibMoneyMarket01_UnsupportedDecimals.selector);
    adminFacet.setTokenConfigs(_tokens, _inputs);
  }
}
