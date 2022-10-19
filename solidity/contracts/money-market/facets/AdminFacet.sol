// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarketStorage } from "../libraries/LibMoneyMarketStorage.sol";

import { IAdminFacet } from "../interfaces/IAdminFacet.sol";

contract AdminFacet is IAdminFacet {
  function setTokenToIbTokens(IbPair[] memory _ibPair) external {
    LibMoneyMarketStorage.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarketStorage.moneyMarketDiamondStorage();

    uint256 _ibPairLength = _ibPair.length;
    for (uint8 _i; _i < _ibPairLength; ) {
      moneyMarketDs.tokenToIbTokens[_ibPair[_i].token] = _ibPair[_i].ibToken;
      moneyMarketDs.ibTokenToTokens[_ibPair[_i].ibToken] = _ibPair[_i].token;
      unchecked {
        _i++;
      }
    }
  }

  function tokenToIbTokens(address _token) external view returns (address) {
    LibMoneyMarketStorage.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarketStorage.moneyMarketDiamondStorage();
    return moneyMarketDs.tokenToIbTokens[_token];
  }

  function ibTokenToTokens(address _ibToken) external view returns (address) {
    LibMoneyMarketStorage.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarketStorage.moneyMarketDiamondStorage();
    return moneyMarketDs.ibTokenToTokens[_ibToken];
  }
}
