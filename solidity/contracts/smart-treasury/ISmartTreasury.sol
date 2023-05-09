// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISmartTreasury {
  error SmartTreasury_AmountTooLow();
  error SmartTreasury_PathConfigNotFound();
  error SmartTreasury_Unauthorized();

  // call to auto split target token to each destination
  function distribute(address[] calldata _tokens) external;

  function setAllocs(
    uint256 _revenueAlloc,
    uint256 _devAlloc,
    uint256 _burnAlloc
  ) external;

  function setRevenueToken(address _revenueToken) external;

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;

  function whitelistedCallers(address _caller) external view returns (bool _allow);
}
