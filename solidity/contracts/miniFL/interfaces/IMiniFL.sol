// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./IRewarder.sol";

interface IMiniFL {
  error MiniFL_DuplicatePool();
  error MiniFL_Forbidden();
  error MiniFL_InvalidArguments();
  error MiniFL_BadRewarder();

  function stakingToken(uint256 _pid) external view returns (IERC20Upgradeable);
}
