// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
*/

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { IERC20 } from "../interfaces/IERC20.sol";

/// @title FakeRouter - 1:1 swap for all token without fee and price impact
contract MockRouter {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public lpToken;
  uint256 public amountAout;
  uint256 public amountBout;

  constructor(address _lpToken) {
    lpToken = _lpToken;
  }

  function WETH() external pure returns (address) {
    return address(0);
  }

  function swapExactTokensForETH(
    uint256, /*amountIn*/
    uint256, /*amountOutMin*/
    address[] calldata, /*path*/
    address, /*to*/
    uint256 /*deadline*/
  ) external pure returns (uint256[] memory amounts) {
    return amounts;
  }

  function swapExactETHForTokens(
    uint256, /*amountOutMin*/
    address[] calldata, /*path*/
    address, /*to*/
    uint256 /*deadline*/
  ) external payable returns (uint256[] memory amounts) {
    return amounts;
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256, /*amountOutMin*/
    address[] calldata path,
    address to,
    uint256 /*deadline*/
  ) external returns (uint256[] memory amounts) {
    amounts = getAmountsOut(amountIn, path);

    address _tokenIn = path[0];
    address _tokenOut = path[path.length - 1];

    uint256 _normalizedAmountIn = amountIn * 10**(18 - IERC20(_tokenIn).decimals());
    uint256 _normalizedAmountOut = _normalizedAmountIn / 10**(18 - IERC20(_tokenOut).decimals());

    IERC20Upgradeable(_tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20Upgradeable(_tokenOut).safeTransfer(to, _normalizedAmountOut);
  }

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256, /*amountInMax*/
    address[] calldata path,
    address to,
    uint256 /*deadline*/
  ) external returns (uint256[] memory amounts) {
    amounts = getAmountsIn(amountOut, path);

    uint256 _normalizedAmountOut = amountOut * 10**(18 - IERC20(path[path.length - 1]).decimals());
    uint256 _normalizedAmountIn = _normalizedAmountOut / 10**(18 - IERC20(path[0]).decimals());

    IERC20Upgradeable(path[0]).safeTransferFrom(msg.sender, address(this), _normalizedAmountIn);
    IERC20Upgradeable(path[path.length - 1]).safeTransfer(to, amountOut);
  }

  function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
    amounts = new uint256[](path.length);
    uint256 _normalizedAmountOut = amountOut * 10**(18 - IERC20(path[path.length - 1]).decimals());

    uint256 _normalizedAmountIn = _normalizedAmountOut;

    amounts[0] = _normalizedAmountIn / 10**(18 - IERC20(path[0]).decimals());
    amounts[1] = _normalizedAmountOut / 10**(18 - IERC20(path[path.length - 1]).decimals());

    return amounts;
  }

  function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
    amounts = new uint256[](path.length);

    uint256 _normalizedAmountIn = amountIn * 10**(18 - IERC20(path[0]).decimals());

    uint256 _normalizedAmountOut = _normalizedAmountIn;

    amounts[0] = _normalizedAmountIn / 10**(18 - IERC20(path[0]).decimals());
    amounts[1] = _normalizedAmountOut / 10**(18 - IERC20(path[path.length - 1]).decimals());

    return amounts;
  }

  function setRemoveLiquidityAmountsOut(uint256 _amountAOut, uint256 _amountBOut) external {
    amountAout = _amountAOut;
    amountBout = _amountBOut;
  }

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256, /*amountAMin*/
    uint256, /*amountBMin*/
    address to,
    uint256 /*deadline*/
  ) public returns (uint256 amountA, uint256 amountB) {
    amountA = amountAout;
    amountB = amountBout;

    IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, address(this), liquidity);
    IERC20Upgradeable(tokenA).safeTransfer(to, amountAout);
    IERC20Upgradeable(tokenB).safeTransfer(to, amountBout);
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256, /*amountAMin*/
    uint256, /*amountBMin*/
    address, /*to*/
    uint256 /*deadline*/
  )
    external
    returns (
      uint256 _amountA,
      uint256 _amountB,
      uint256 _liquidity
    )
  {
    _amountA = amountADesired;
    _amountB = amountBDesired;

    {
      uint256 _normalizedTokenA = amountADesired * 10**(18 - IERC20(tokenA).decimals());
      uint256 _normalizedTokenB = amountBDesired * 10**(18 - IERC20(tokenB).decimals());

      _liquidity = (_normalizedTokenA + _normalizedTokenB) / 2;
    }

    IERC20Upgradeable(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);

    IERC20Upgradeable(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

    IERC20Upgradeable(lpToken).safeTransfer(msg.sender, _liquidity);
  }
}
