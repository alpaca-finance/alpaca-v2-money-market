// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest } from "../base/BaseTest.sol";

// interfaces
import { ICollateralFacet } from "../../contracts/money-market/facets/CollateralFacet.sol";
import { IDepositFacet } from "../../contracts/money-market/facets/DepositFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { IBorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

abstract contract MoneyMarket_BaseTest is BaseTest {
  address internal moneyMarketDiamond;

  IAdminFacet internal adminFacet;
  IDepositFacet internal depositFacet;
  ICollateralFacet internal collateralFacet;
  IBorrowFacet internal borrowFacet;

  function setUp() public virtual {
    (moneyMarketDiamond) = deployPoolDiamond();

    depositFacet = IDepositFacet(moneyMarketDiamond);
    collateralFacet = ICollateralFacet(moneyMarketDiamond);
    adminFacet = IAdminFacet(moneyMarketDiamond);
    borrowFacet = IBorrowFacet(moneyMarketDiamond);

    weth.mint(ALICE, 1000 ether);
    usdc.mint(ALICE, 1000 ether);
    isolateToken.mint(ALICE, 1000 ether);

    weth.mint(BOB, 1000 ether);
    usdc.mint(BOB, 1000 ether);
    isolateToken.mint(BOB, 1000 ether);

    vm.startPrank(ALICE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);
    isolateToken.approve(moneyMarketDiamond, type(uint256).max);
    vm.stopPrank();

    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](3);
    _ibPair[0] = IAdminFacet.IbPair({
      token: address(weth),
      ibToken: address(ibWeth)
    });
    _ibPair[1] = IAdminFacet.IbPair({
      token: address(usdc),
      ibToken: address(ibUsdc)
    });
    _ibPair[2] = IAdminFacet.IbPair({
      token: address(isolateToken),
      ibToken: address(ibIsolateToken)
    });

    adminFacet.setTokenToIbTokens(_ibPair);

    IAdminFacet.AssetTierInput[]
      memory _assetTierInputs = new IAdminFacet.AssetTierInput[](3);

    _assetTierInputs[0] = IAdminFacet.AssetTierInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL
    });

    _assetTierInputs[1] = IAdminFacet.AssetTierInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL
    });

    _assetTierInputs[2] = IAdminFacet.AssetTierInput({
      token: address(isolateToken),
      tier: LibMoneyMarket01.AssetTier.ISOLATE
    });

    adminFacet.setAssetTiers(_assetTierInputs);
  }
}
