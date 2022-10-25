// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IAdminFacet {
  struct IbPair {
    address token;
    address ibToken;
  }

  struct AssetTierInput {
    address token;
    LibMoneyMarket01.AssetTier tier;
  }

  function setTokenToIbTokens(IbPair[] memory _ibPair) external;

  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);

  function setAssetTiers(AssetTierInput[] memory _assetTierInputs) external;

  function assetTiers(address _token)
    external
    view
    returns (LibMoneyMarket01.AssetTier);
}
