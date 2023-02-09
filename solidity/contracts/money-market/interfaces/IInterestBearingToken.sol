// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

  function totalAssets() external view returns (uint256);

  function totalSupply() external view returns (uint256);
}
