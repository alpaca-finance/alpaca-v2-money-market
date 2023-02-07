// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IRewarder.sol";

interface IMiniFL {
  error MiniFL_DuplicatePool();
  error MiniFL_Forbidden();
  error MiniFL_InvalidArguments();
  error MiniFL_BadRewarder();
  error MiniFL_InsufficientFundedAmount();
  error MiniFL_Unauthorized();

  function poolLength() external view returns (uint256);

  function stakingTokens(uint256 _pid) external view returns (address);

  function getStakingReserves(uint256 _pid) external view returns (uint256);

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;
}
