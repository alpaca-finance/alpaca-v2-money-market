// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IAdminFacet {
  struct IbPair {
    address token;
    address ibToken;
  }

  struct TokenConfigInput {
    address token;
    LibMoneyMarket01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 maxToleranceExpiredSecond;
  }

  function setTokenToIbTokens(IbPair[] memory _ibPair) external;

  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setNonCollatBorrower(address _borrower, bool _isOk) external;

  function tokenConfigs(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function setInterestModel(address _token, address model) external;

  function setOracle(address _oracle) external;

  function setRepurchasersOk(address[] memory list, bool _isOk) external;
}
