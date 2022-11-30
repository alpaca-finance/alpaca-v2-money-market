// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ILiquidationStrategy } from "../../contracts/money-market/interfaces/ILiquidationStrategy.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";

contract MockLiquidationStrategy is ILiquidationStrategy {
  using SafeERC20 for ERC20;

  MockChainLinkPriceOracle internal _mockOracle;

  constructor(address _oracle) {
    _mockOracle = MockChainLinkPriceOracle(_oracle);
  }

  /// @dev swap collat for exact repay amount and send remaining collat to caller
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _repayAmount,
    address _repayTo,
    address _rewardTo
  ) external {
    (uint256 _priceCollatPerRepayToken, ) = _mockOracle.getPrice(_collatToken, _repayToken);

    uint256 _collatAmountBefore = ERC20(_collatToken).balanceOf(address(this));

    ERC20(_repayToken).safeTransfer(_repayTo, _repayAmount);

    uint256 _collatAmountAfter = _collatAmountBefore -
      ((_repayAmount * 10**ERC20(_repayToken).decimals()) / _priceCollatPerRepayToken);

    ERC20(_collatToken).safeTransfer(_rewardTo, _collatAmountAfter);
  }
}
