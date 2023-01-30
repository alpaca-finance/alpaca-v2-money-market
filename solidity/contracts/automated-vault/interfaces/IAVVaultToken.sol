// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAVVaultToken is IERC20 {
  function mint(address to, uint256 amount) external;

  function burn(address from, uint256 amount) external;
}
