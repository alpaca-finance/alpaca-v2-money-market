// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "../interfaces/IERC20.sol";
import { MockAlpacaV2Oracle } from "./MockAlpacaV2Oracle.sol";

/// @title FakeRouter - 1:1 swap for all token without fee and price impact
contract MockRouter02 {
  address public lpToken;
  uint256 public amountAout;
  uint256 public amountBout;

  MockAlpacaV2Oracle private _oracle;

  constructor(address _lpToken, address oracle_) {
    lpToken = _lpToken;
    _oracle = MockAlpacaV2Oracle(oracle_);
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
    uint256 _normalizedAmountIn = amountIn * 10**(18 - IERC20(path[0]).decimals());

    (uint256 _tokenInPrice, ) = _oracle.getTokenPrice(path[0]);
    (uint256 _tokenOutPrice, ) = _oracle.getTokenPrice(path[path.length - 1]);

    uint256 _normalizedAmountOut = (_normalizedAmountIn * _tokenInPrice) / _tokenOutPrice;

    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    IERC20(path[path.length - 1]).transfer(
      to,
      _normalizedAmountOut / 10**(18 - IERC20(path[path.length - 1]).decimals())
    );
  }

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256, /*amountInMax*/
    address[] calldata path,
    address to,
    uint256 /*deadline*/
  ) external returns (uint256[] memory amounts) {
    amounts = getAmountsIn(amountOut, path);
    IERC20(path[0]).transferFrom(msg.sender, address(this), amountOut);
    IERC20(path[path.length - 1]).transfer(to, amountOut);
  }

  function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
    amounts = new uint256[](path.length);
    uint256 _normalizedAmountOut = amountOut * 10**(18 - IERC20(path[path.length - 1]).decimals());

    (uint256 _tokenInPrice, ) = _oracle.getTokenPrice(path[0]);
    (uint256 _tokenOutPrice, ) = _oracle.getTokenPrice(path[path.length - 1]);

    uint256 _normalizedAmountIn = (_normalizedAmountOut * _tokenOutPrice) / _tokenInPrice;

    amounts[0] = _normalizedAmountIn / 10**(18 - IERC20(path[0]).decimals());
    amounts[1] = _normalizedAmountOut / 10**(18 - IERC20(path[path.length - 1]).decimals());

    return amounts;
  }

  function getAmountsOut(uint256 amountIn, address[] memory path) public pure returns (uint256[] memory amounts) {
    amounts = new uint256[](path.length);
    for (uint256 i = 0; i < path.length; i++) {
      amounts[i] = amountIn;
    }
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
    IERC20(lpToken).transferFrom(msg.sender, address(this), liquidity);
    IERC20(tokenA).transfer(to, amountAout);
    IERC20(tokenB).transfer(to, amountBout);
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
      uint256 amountA,
      uint256 amountB,
      uint256 liquidity
    )
  {
    amountA = amountADesired;
    amountB = amountBDesired;
    liquidity = (amountADesired + amountBDesired) / 2;

    IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);

    IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);

    IERC20(lpToken).transfer(msg.sender, liquidity);
  }
}
