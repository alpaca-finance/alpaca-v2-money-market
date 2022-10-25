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
    _ibPair[0] = IAdminFacet.IbPair({
      token: _depositToken,
      ibToken: _ibDepositToken
    });

    adminFacet.setTokenToIbTokens(_ibPair);

    assertEq(adminFacet.tokenToIbTokens(_depositToken), _ibDepositToken);
    assertEq(adminFacet.ibTokenToTokens(_ibDepositToken), _depositToken);
  }

  function testCorrectness_WhenAdminSetTokenConfig_ShouldWork() external {
    address _token = address(9998);

    IAdminFacet.TokenConfigInput[]
      memory _intputs = new IAdminFacet.TokenConfigInput[](1);

    _intputs[0] = IAdminFacet.TokenConfigInput({
      token: _token,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 5000,
      borrowingFactor: 6000
    });

    adminFacet.setTokenConfigs(_intputs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = adminFacet.tokenConfigs(
      _token
    );

    // assertEq not accept enum
    assertTrue(_tokenConfig.tier == LibMoneyMarket01.AssetTier.COLLATERAL);
    assertEq(_tokenConfig.collateralFactor, 5000);
    assertEq(_tokenConfig.borrowingFactor, 6000);
  }
}
