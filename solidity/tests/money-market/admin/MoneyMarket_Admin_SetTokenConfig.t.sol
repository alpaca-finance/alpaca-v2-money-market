// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "../MoneyMarket_BaseTest.t.sol";

// libs
import { LibMoneyMarket01 } from "../../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract MoneyMarket_Admin_SetTokenConfigTest is MoneyMarket_BaseTest {
  function setUp() public override {
    super.setUp();
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

  function testRevert_WhenNonOwnerSetTokenConfig() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
    });

    vm.prank(ALICE);
    vm.expectRevert("LibDiamond: Must be contract owner");
    adminFacet.setTokenConfigs(_inputs);
  }

  function testRevert_WhenSetTokenConfigWithInvalidCollateralFactor() external {
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(9998),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 12000,
      borrowingFactor: 5000,
      maxCollateral: 1000e18,
      maxBorrow: 100e18
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
      maxBorrow: 100e18
    });

    // borrowing factor is more than MAX_BPS
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);

    // borrowing factor is zero
    _inputs[0].borrowingFactor = 0;
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
      maxBorrow: 100e18
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
      maxBorrow: 1e41
    });

    // maxBorrow is more than MAX_BPS
    vm.expectRevert(abi.encodeWithSelector(IAdminFacet.AdminFacet_InvalidArguments.selector));
    adminFacet.setTokenConfigs(_inputs);
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

  function testCorrectness_WhenLYFAdminSetMaxNumOfToken_ShouldCorrect() external {
    (uint8 _maxNumOfCollatBefore, uint8 _maxNumOfDebtBefore, uint8 _maxNumOfNonColaltDebtBefore) = viewFacet
      .getMaxNumOfToken();
    // 3 is set from basetest
    assertEq(_maxNumOfCollatBefore, 3);
    assertEq(_maxNumOfDebtBefore, 3);
    assertEq(_maxNumOfNonColaltDebtBefore, 3);
    adminFacet.setMaxNumOfToken(4, 5, 6);

    (uint8 _maxNumOfCollatAfter, uint8 _maxNumOfDebtAfter, uint8 _maxNumOfNonColaltDebtAfter) = viewFacet
      .getMaxNumOfToken();
    assertEq(_maxNumOfCollatAfter, 4);
    assertEq(_maxNumOfDebtAfter, 5);
    assertEq(_maxNumOfNonColaltDebtAfter, 6);
  }
}