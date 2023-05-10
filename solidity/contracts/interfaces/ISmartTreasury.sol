// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISmartTreasury {
  error SmartTreasury_InvalidAddress();
  error SmartTreasury_PathConfigNotFound();
  error SmartTreasury_Unauthorized();

  struct AllocPoints {
    uint16 revenueAllocPoint;
    uint16 devAllocPoint;
    uint16 burnAllocPoint;
  }

  function distribute(address[] calldata _tokens) external;

  function setAllocPoints(AllocPoints calldata _allocPoints) external;

  function setRevenueToken(address _revenueToken) external;

  function setTreasuryAddresses(
    address _revenueTreasury,
    address _devTreasury,
    address _burnTreasury
  ) external;

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;
}
