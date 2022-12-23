// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../contracts/money-market/facets/AdminFacet.sol";

contract MoneyMarket_AdminFacetTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_WhenAdminSetTokenToIbTokens_ShouldWork() external {
    address _depositToken = address(9998);
    address _ibDepositToken = address(9999);

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](1);
    _ibPair[0] = IAdminFacet.IbPair({ token: _depositToken, ibToken: _ibDepositToken });

    adminFacet.setIbPairs(_ibPair);

    assertEq(viewFacet.getIbTokenFromToken(_depositToken), _ibDepositToken);
    assertEq(viewFacet.getTokenFromIbToken(_ibDepositToken), _depositToken);
  }

  function testCorrectness_WhenAdminSetTokenConfig_ShouldWork() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });

    adminFacet.setTokenConfigs(_inputs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = viewFacet.getTokenConfig(address(weth));

    // assertEq not accept enum
    assertTrue(_tokenConfig.tier == LibMoneyMarket01.AssetTier.COLLATERAL);
    assertEq(_tokenConfig.collateralFactor, 5000);
    assertEq(_tokenConfig.borrowingFactor, 6000);
  }

  function testCorrectness_WhenNonAdminSetSomeConfig_ShouldRevert() external {
    vm.startPrank(ALICE);

    // try to setIbPairs
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](1);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(9998), ibToken: address(9999) });
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setIbPairs(_ibPair);

    // try to setTokenConfigs
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTokenConfigs(_inputs);

    vm.stopPrank();
  }

  function testRevert_FailedSanityCheck() external {
    // address 0
    vm.expectRevert();
    adminFacet.setInterestModel(address(weth), address(0));

    vm.expectRevert();
    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(0));

    vm.expectRevert();
    adminFacet.setOracle(address(0));

    // wrong contract
    vm.expectRevert();
    adminFacet.setInterestModel(address(weth), address(btc));

    vm.expectRevert();
    adminFacet.setNonCollatInterestModel(ALICE, address(weth), address(btc));

    vm.expectRevert();
    adminFacet.setOracle(address(btc));
  }

  function testRevert_WhenSetTokenConfigWithInvalidCollateralFactor() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 12000,
      borrowingFactor: 5000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_WhenSetTokenConfigWithInvalidBorrowingFactor() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 6000,
      borrowingFactor: 12000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    // borrowing factor is more than MAX_BPS
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_WhenSetTokenConfigWithInvalidMaxCollateral() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 12000,
      borrowingFactor: 5000,
      maxCollateral: 1e41,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    // maxCollateral is more than MAX_BPS
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_WhenSetTokenConfigWithInvalidMaxBorrow() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 12000,
      borrowingFactor: 5000,
      maxCollateral: 1000e18,
      maxBorrow: 1e41,
      maxToleranceExpiredSecond: block.timestamp
    });

    // maxBorrow is more than MAX_BPS
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);
  }
}
