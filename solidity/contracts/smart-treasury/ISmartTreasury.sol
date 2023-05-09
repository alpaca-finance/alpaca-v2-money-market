// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISmartTreasury {
  error SmartTreasury_PathConfigNotFound();
  error SmartTreasury_Unauthorized();

  // call to auto split target token to each destination
  function distribute(address[] calldata _tokens) external;

  function setAllocPoints(
    uint256 _revenueAllocPoint,
    uint256 _devAllocPoint,
    uint256 _burnAllocPoint
  ) external;

  function setRevenueToken(address _revenueToken) external;

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;
}
