// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IInterestBearingToken is IERC20 {
  function totalAssets() external view returns (uint256);

  function totalSupply() external view returns (uint256);
}
