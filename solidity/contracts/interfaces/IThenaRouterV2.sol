// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IThenaRouterV2 {
  struct route {
    address from;
    address to;
    bool stable;
  }

  function swapExactTokensForTokensSimple(
    uint256 amountIn,
    uint256 amountOutMin,
    address tokenFrom,
    address tokenTo,
    bool stable,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    route[] calldata routes,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}
