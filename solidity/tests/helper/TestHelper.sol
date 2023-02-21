// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";

import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";

library TestHelper {
  function openMarketWithDefaultTokenConfig(address _moneyMarketDiamond, address _token)
    internal
    returns (InterestBearingToken)
  {
    IAdminFacet _adminFacet = IAdminFacet(_moneyMarketDiamond);
    IAdminFacet.TokenConfigInput memory _defaultTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(30 ether, IERC20(_token).decimals()),
      maxCollateral: normalizeEther(100 ether, IERC20(_token).decimals())
    });
    return InterestBearingToken(_adminFacet.openMarket(_token, _defaultTokenConfigInput, _defaultTokenConfigInput));
  }

  function normalizeEther(uint256 _ether, uint256 _decimal) internal pure returns (uint256 _normalizedEther) {
    _normalizedEther = _ether / 10**(18 - _decimal);
  }
}
