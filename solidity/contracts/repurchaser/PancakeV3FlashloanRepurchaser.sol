// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IPancakeV3SwapCallback } from "./interfaces/IPancakeV3SwapCallback.sol";

import { LibSafeToken } from "./libraries/LibSafeToken.sol";

contract PancakeV3FlashLoanRepurchaser is IPancakeV3SwapCallback {
  using LibSafeToken for IERC20;

  error UniswapV3FlashLoanRepurchaser_Unauthorized();
  error UniswapV3FlashLoanRepurchaser_BadPool();

  address constant PANCAKESWAP_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;
  bytes32 internal constant POOL_INIT_CODE_HASH = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;

  // TODO: change to constant when deploy
  address public immutable owner;
  IMoneyMarket public immutable moneyMarketDiamond;
  IMoneyMarketAccountManager public immutable accountManager;

  constructor(
    address _owner,
    address _moneyMarketDiamond,
    address _accountManager
  ) {
    owner = _owner;
    moneyMarketDiamond = IMoneyMarket(_moneyMarketDiamond);
    accountManager = IMoneyMarketAccountManager(_accountManager);
  }

  function withdrawToken(address _token) external {
    if (msg.sender != owner) revert UniswapV3FlashLoanRepurchaser_Unauthorized();
    IERC20(_token).safeTransfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  function initRepurchase(bytes calldata data) external {
    (
      ,
      ,
      address _debtToken,
      address _underlyingOfCollatToken,
      ,
      uint24 _fee,
      uint256 _desiredRepayAmount
    ) = _decodeData(data);

    address _poolAddress = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _fee);

    // swap from underlyingOfColalt to debt aka flashloan debt, repurchase and repay underlyingOfCollat
    if (_debtToken < _underlyingOfCollatToken) {
      // debtToken is token0, underlyingOfCollatToken is token1
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        false, // swap token1 to token0
        -int256(_desiredRepayAmount), // negative means exact output
        1461446703485210103287273052203988822378723970341, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = false`
        data
      );
    } else {
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        true, // swap token0 to token1
        int256(_desiredRepayAmount), // positive means exact input
        4295128740, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = true`
        data
      );
    }
  }

  function pancakeV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken,
      address _collatToken,
      uint24 _flashloanFee,
      uint256 _desiredRepayAmount
    ) = _decodeData(data);

    // verify `msg.sender` is pool
    address pool = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _flashloanFee);
    if (msg.sender != pool) revert UniswapV3FlashLoanRepurchaser_BadPool();

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan on positve amountDelta side. only one side can be positive.
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, uint256(amount0Delta > 0 ? amount0Delta : amount1Delta));
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
  }

  function _repurchaseAndWithdrawIb(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    uint256 _desiredRepayAmount
  ) internal {
    // approve max and reset because we don't know exact repay amount
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), type(uint256).max);
    uint256 _collatTokenReceived = moneyMarketDiamond.repurchase(
      _account,
      _subAccountId,
      _debtToken,
      _collatToken,
      _desiredRepayAmount
    );
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), 0);

    // fine to approve exact amount because withdraw will spend it all
    IERC20(_collatToken).safeApprove(address(accountManager), _collatTokenReceived);
    accountManager.withdraw(_collatToken, _collatTokenReceived);
  }

  function _computePoolAddress(
    address tokenA,
    address tokenB,
    uint24 fee
  ) internal pure returns (address poolAddress) {
    if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex"ff",
                PANCAKESWAP_V3_POOL_DEPLOYER,
                keccak256(abi.encode(tokenA, tokenB, fee)),
                POOL_INIT_CODE_HASH
              )
            )
          )
        )
      );
  }

  function _decodeData(bytes memory data)
    internal
    pure
    returns (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint24 _flashloanFee,
      uint256 _desiredRepayAmount
    )
  {
    return abi.decode(data, (address, uint256, address, address, address, uint24, uint256));
  }
}
