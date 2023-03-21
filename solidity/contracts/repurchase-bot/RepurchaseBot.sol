// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IPancakeCallee } from "solidity/contracts/repurchase-bot/interfaces/IPancakeCallee.sol";
import { IPancakeRouter01 } from "solidity/contracts/repurchase-bot/interfaces/IPancakeRouter01.sol";

contract RepurchaseBot is IPancakeCallee {
  error Unauthorized();

  // TODO: change to constant when deploy
  address public immutable owner;
  IMoneyMarket public immutable moneyMarketDiamond;
  IPancakeRouter01 public immutable pancakeRouter;

  modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
  }

  constructor(address _moneyMarketDiamond, address _pancakeRouter) {
    owner = msg.sender;
    moneyMarketDiamond = IMoneyMarket(_moneyMarketDiamond);
    pancakeRouter = IPancakeRouter01(_pancakeRouter);
  }

  //   function repurchase(
  //     address _account,
  //     uint256 _subAccountId,
  //     address _debtToken,
  //     address _collatToken,
  //     uint256 _desiredRepayAmount
  //   ) external onlyOwner {}

  function withdrawToken(address _token) external onlyOwner {
    IERC20(_token).transfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  function pancakeCall(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _collatToken,
      uint256 _desiredRepayAmount
    ) = abi.decode(data, (address, uint256, address, address, uint256));

    (address _token0, ) = sortTokens(_collatToken, _debtToken);
    address[] memory _path = new address[](2);
    _path[0] = _debtToken;
    _path[1] = _collatToken;
    uint256[] memory _amounts = pancakeRouter.getAmountsOut(_token0 == _debtToken ? amount0 : amount1, _path);
    uint256 _amountRepayFlashswap = _amounts[1];

    uint256 _collatTokenBefore = IERC20(_collatToken).balanceOf(address(this));

    moneyMarketDiamond.repurchase(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    uint256 _collatTokenAfter = IERC20(_collatToken).balanceOf(address(this)) - _collatTokenBefore;

    if (_collatTokenAfter - _amountRepayFlashswap == 0) revert();

    IERC20(_collatToken).transfer(msg.sender, _amountRepayFlashswap);
  }

  // returns sorted token addresses, used to handle return values from pairs sorted in this order
  function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
    require(tokenA != tokenB, "PancakeLibrary: IDENTICAL_ADDRESSES");
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "PancakeLibrary: ZERO_ADDRESS");
  }
}

// test case
//
// assume
// BTC = $2000, CF = 0.9, BF = 0.9
// ETH = $1000, CF = 0.9, BF = 0.9
// repurhcase bonus 5%
// liquidate threshold 50%
//
// underwater position
// collat: 1 BTC = 1800 BP
// debt: 2 ETH = 2222.22 UBP
//
// steps
// get user collat, debt, factors and calculate repurchase amount
//   - max UBP repurchasable = UBP * liqThresh
//                           = 2222.22 * 0.5 = 1111.11 UBP = 1 ETH
//   - collatAmountOut = repayAmount * debtTokenPriceWithPremium / collatTokenPrice
//                     = 1 * 1050 / 2000 = 0.525 BTC
// flashloan 1 ETH from ETH/BTC pair (expected 0.50125 BTC back)
// repurchase 1 ETH (we now have 0.525 BTC, 0 ETH)
// repay 0.50125 BTC (we are left with 0.02375 BTC profit)
