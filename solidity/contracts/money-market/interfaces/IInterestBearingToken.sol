// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "./IERC20.sol";

interface IInterestBearingToken is IERC20 {
  function initialize(address underlying_, address owner_) external;

  function onDeposit(
    address receiver,
    uint256 assets,
    uint256 shares
  ) external;

  function onWithdraw(
    address owner,
    address receiver,
    uint256 assets,
    uint256 shares
  ) external;

  function decimals() external view returns (uint8);

  function convertToShares(uint256 assets) external view returns (uint256 shares);

  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  function totalAssets() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function mint(uint256 shares, address receiver) external returns (uint256 assets);
}
