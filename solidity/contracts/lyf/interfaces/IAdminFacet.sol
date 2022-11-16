// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";

interface IAdminFacet {
  struct TokenConfigInput {
    address token;
    LibLYF01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 maxToleranceExpiredSecond;
  }

  function setOracle(address _oracle) external;

  function oracle() external view returns (address);

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;
}
