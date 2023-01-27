// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// dependencies
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibSafeToken } from "../../contracts/money-market/libraries/LibSafeToken.sol";

// interfaces
import { ILiquidationStrategy } from "../../contracts/money-market/interfaces/ILiquidationStrategy.sol";

// mocks
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";

import { console } from "solidity/tests/utils/console.sol";

contract MockLiquidationStrategy is ILiquidationStrategy, Ownable {
  using SafeERC20 for ERC20;

  MockAlpacaV2Oracle internal _mockOracle;

  mapping(address => bool) public callersOk;

  constructor(address _oracle) {
    _mockOracle = MockAlpacaV2Oracle(_oracle);
  }

  /// @dev swap collat for exact repay amount and send remaining collat to caller
  function executeLiquidation(
    address _collatToken,
    address _repayToken,
    uint256 _collatAmountIn,
    uint256 _repayAmount,
    uint256 /* _minReceive */
  ) external {
    console.log("MockLiquidationStrategy:executeLiquidation");

    (uint256 _collatPrice, ) = _mockOracle.getTokenPrice(_collatToken);
    (uint256 _repayTokenPrice, ) = _mockOracle.getTokenPrice(_repayToken);
    console.log("MockLiquidationStrategy:executeLiquidation[1]");
    uint256 _priceCollatPerRepayToken = (_collatPrice * 1e18) / _repayTokenPrice;
    console.log("MockLiquidationStrategy:executeLiquidation[2]");
    console.log("MockLiquidationStrategy:executeLiquidation:_collatPrice", _collatPrice);
    console.log("MockLiquidationStrategy:executeLiquidation:_repayTokenPrice", _repayTokenPrice);
    console.log("MockLiquidationStrategy:executeLiquidation:_priceCollatPerRepayToken", _priceCollatPerRepayToken);
    uint256 _collatSold = (_repayAmount * 10**ERC20(_repayToken).decimals()) / _priceCollatPerRepayToken;
    uint256 _actualCollatSold = _collatSold > _collatAmountIn ? _collatAmountIn : _collatSold;
    uint256 _actualRepayAmount = (_actualCollatSold * _priceCollatPerRepayToken) / 10**ERC20(_collatToken).decimals();
    console.log("MockLiquidationStrategy:executeLiquidation[3]");
    ERC20(_repayToken).safeTransfer(msg.sender, _actualRepayAmount);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountIn - _actualCollatSold);
  }

  /// @notice Set callers ok
  /// @param _callers A list of caller addresses
  /// @param _isOk An ok flag
  function setCallersOk(address[] calldata _callers, bool _isOk) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i = 0; _i < _length; ) {
      callersOk[_callers[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }
}
