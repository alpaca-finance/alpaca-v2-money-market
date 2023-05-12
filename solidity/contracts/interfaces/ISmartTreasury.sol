// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface ISmartTreasury {
  error SmartTreasury_InvalidAddress();
  error SmartTreasury_InvalidAllocPoint();
  error SmartTreasury_SlippageTolerance();
  error SmartTreasury_PathConfigNotFound();
  error SmartTreasury_Unauthorized();

  function distribute(address[] calldata _tokens) external;

  function setAllocPoints(
    uint16 _revenueAllocPoint,
    uint16 _devAllocPoint,
    uint16 _burnAllocPoint
  ) external;

  function setRevenueToken(address _revenueToken) external;

  function setSlippageToleranceBps(uint16 _slippageToleranceBps) external;

  function setTreasuryAddresses(
    address _revenueTreasury,
    address _devTreasury,
    address _burnTreasury
  ) external;

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;

  function withdraw(address[] calldata _tokens, address _to) external;
}
