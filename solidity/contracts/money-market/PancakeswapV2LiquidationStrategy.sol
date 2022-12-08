// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { ILiquidationStrategy } from "./interfaces/ILiquidationStrategy.sol";
import { IPancakeRouter02 } from "../lyf/interfaces/IPancakeRouter02.sol";

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

    uint256 _collatBalance = ERC20(_collatToken).balanceOf(address(this));

    ERC20(_collatToken).safeApprove(address(router), _collatBalance);

    uint256[] memory _amountsIn = router.getAmountsIn(_repayAmount, path);
    // _amountsIn[0] = collat that is required to swap for _repayAmount
    if (_collatBalance >= _amountsIn[0]) {
      // swapTokensForExactTokens will fail if _collatBalance is not enough to swap for _repayAmount during low liquidity period
      router.swapTokensForExactTokens(_repayAmount, _collatBalance, path, _repayTo, block.timestamp);
    } else {
      router.swapExactTokensForTokens(_collatBalance, _minReceive, path, _repayTo, block.timestamp);
    }

    ERC20(_collatToken).safeApprove(address(router), 0);

    ERC20(_collatToken).safeTransfer(_repayTo, ERC20(_collatToken).balanceOf(address(this)));
  }
}
