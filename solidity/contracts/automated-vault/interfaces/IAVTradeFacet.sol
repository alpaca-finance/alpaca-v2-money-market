// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAVTradeFacet {
  error AVTradeFacet_InvalidToken(address _token);

  event LogOpenMarket(address indexed _caller, address indexed _token, address _shareToken);

  function openVault(address _token) external returns (address _newShareToken);

  function deposit(
    address _token,
    uint256 _amountIn,
    uint256 _minShareOut
  ) external;

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut
  ) external;
}
