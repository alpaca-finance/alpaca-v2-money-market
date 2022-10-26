// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest } from "./MoneyMarket_BaseTest.t.sol";

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

  function testCorrectness_WhenAdminSetAssetTier_ShouldWork() external {
    address _token = address(9998);

    IAdminFacet.AssetTierInput[]
      memory _assetTierInputs = new IAdminFacet.AssetTierInput[](1);

    _assetTierInputs[0] = IAdminFacet.AssetTierInput({
      token: _token,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL
    });

    adminFacet.setAssetTiers(_assetTierInputs);

    // assertEq not accept enum
    assert(
      adminFacet.assetTiers(_token) == LibMoneyMarket01.AssetTier.COLLATERAL
    );
  }
}
