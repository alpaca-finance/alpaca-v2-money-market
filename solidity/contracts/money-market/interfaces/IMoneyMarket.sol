// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

import { IViewFacet } from "./IViewFacet.sol";
import { ILendFacet } from "./ILendFacet.sol";
import { IAdminFacet } from "./IAdminFacet.sol";
import { IBorrowFacet } from "./IBorrowFacet.sol";
import { INonCollatBorrowFacet } from "./INonCollatBorrowFacet.sol";
import { ICollateralFacet } from "./ICollateralFacet.sol";
import { ILiquidationFacet } from "./ILiquidationFacet.sol";

interface IMoneyMarket is
  IViewFacet,
  IAdminFacet,
  IBorrowFacet,
  INonCollatBorrowFacet,
  ICollateralFacet,
  ILiquidationFacet,
  ILendFacet
{}
