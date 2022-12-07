// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeRouter02 } from "../lyf/interfaces/IPancakeRouter02.sol";

import { console } from "solidity/tests/utils/console.sol";

contract PancakeswapV2LiquidationStrategy is ILiquidationStrategy {
  using SafeERC20 for ERC20;

  error PancakeswapV2LiquidationStrategy_InvalidPath();

  IPancakeRouter02 internal router;

  constructor(address _router) {
    router = IPancakeRouter02(_router);
  }

  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _repayAmount,
    address _repayTo,
    bytes calldata _data
  ) external {
    (address[] memory path, uint256 _minReceive) = abi.decode(_data, (address[], uint256));
    // validate path[0] == _collatToken ??
    if (path[path.length - 1] != _repayToken) {
      revert PancakeswapV2LiquidationStrategy_InvalidPath();
    }

    uint256 _collatAmountBefore = ERC20(_collatToken).balanceOf(address(this));

    ERC20(_collatToken).increaseAllowance(address(router), _collatAmountBefore);

    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, path);
    if (_amountsIn[0] <= _collatAmountBefore) {
      // swapTokensForExactTokens will fail if _collatAmountBefore is not enough to swap for _repayAmount during low liquidity period
      router.swapTokensForExactTokens(_repayAmount, _collatAmountBefore, path, _repayTo, block.timestamp);
    } else {
      router.swapExactTokensForTokens(_collatAmountBefore, _minReceive, path, _repayTo, block.timestamp);
    }

    ERC20(_collatToken).safeTransfer(_repayTo, ERC20(_collatToken).balanceOf(address(this)));
  }
}
