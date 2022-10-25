// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

import { IAdminFacet } from "../interfaces/IAdminFacet.sol";

contract AdminFacet is IAdminFacet {
  // TODO: validate role
  function setTokenToIbTokens(IbPair[] memory _ibPair) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _ibPairLength = _ibPair.length;
    for (uint8 _i; _i < _ibPairLength; ) {
      moneyMarketDs.tokenToIbTokens[_ibPair[_i].token] = _ibPair[_i].ibToken;
      moneyMarketDs.ibTokenToTokens[_ibPair[_i].ibToken] = _ibPair[_i].token;
      unchecked {
        _i++;
      }
    }
  }

  // TODO: validate role
  function setAssetTiers(AssetTierInput[] memory _assetTierInputs) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _inputLength = _assetTierInputs.length;
    for (uint8 _i; _i < _inputLength; ) {
      moneyMarketDs.assetTiers[_assetTierInputs[_i].token] = _assetTierInputs[
        _i
      ].tier;

      // TODO: set collateral factor and borrow factor on tier change

      unchecked {
        _i++;
      }
    }
  }

  function tokenToIbTokens(address _token) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.tokenToIbTokens[_token];
  }

  function ibTokenToTokens(address _ibToken) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.ibTokenToTokens[_ibToken];
  }

  function assetTiers(address _token)
    external
    view
    returns (LibMoneyMarket01.AssetTier)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.assetTiers[_token];
  }
}
