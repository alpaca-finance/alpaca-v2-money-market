// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IPancakeCallee } from "solidity/contracts/repurchaser/interfaces/IPancakeCallee.sol";
import { IPancakeRouter02 } from "solidity/contracts/repurchaser/interfaces/IPancakeRouter02.sol";
import { IPancakePair } from "solidity/contracts/repurchaser/interfaces/IPancakePair.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IPancakeV3SwapCallback } from "./interfaces/IPancakeV3SwapCallback.sol";

import { LibSafeToken } from "./libraries/LibSafeToken.sol";

contract FlashLoanRepurchaser is IPancakeV3SwapCallback, IPancakeCallee {
  using LibSafeToken for IERC20;

  error FlashLoanRepurchaser_Unauthorized();
  error FlashLoanRepurchaser_BadPool();

  IPancakeRouter02 internal constant pancakeV2Router = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
  address internal constant PANCAKE_V2_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
  bytes32 internal constant PANCAKE_V2_POOL_INIT_CODE_HASH =
    0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;

  address internal constant PANCAKE_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;
  bytes32 internal constant PANCAKE_V3_POOL_INIT_CODE_HASH =
    0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;
  uint160 internal constant MAX_SQRTX96_PRICE = 1461446703485210103287273052203988822378723970341;
  uint160 internal constant MIN_SQRTX96_PRICE = 4295128740;

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
    if (msg.sender != owner) revert FlashLoanRepurchaser_Unauthorized();
    IERC20(_token).safeTransfer(owner, IERC20(_token).balanceOf(address(this)));
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

  // ==============
  // Pancakeswap V2
  // ==============

  function pancakeV2SingleHopFlashSwapRepurchase(bytes calldata _data) external {
    (, , address _debtToken, address _underlyingOfCollatToken, , uint256 _desiredRepayAmount) = _decodeV2Data(_data);

    IPancakePair(_computeV2PoolAddress(_debtToken, _underlyingOfCollatToken)).swap(
      _desiredRepayAmount,
      0,
      address(this),
      _data
    );
  }

  function pancakeCall(
    address, /* _sender */
    uint256 _amount0,
    uint256 _amount1,
    bytes calldata _data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken,
      address _collatToken,
      uint256 _desiredRepayAmount
    ) = _decodeV2Data(_data);

    // verify `msg.sender` is pool
    address _pool = _computeV2PoolAddress(_debtToken, _underlyingOfCollatToken);
    if (msg.sender != _pool) revert FlashLoanRepurchaser_BadPool();

    // currently support only single-hop
    address[] memory _path = new address[](2);
    _path[0] = _underlyingOfCollatToken;
    _path[1] = _debtToken;
    // we swap from underlyingOfCollat (tokenIn) to debt (tokenOut)
    // so we use `getAmountsIn` to find amount to repay flashloan
    uint256[] memory _amounts = pancakeV2Router.getAmountsIn(
      // `_debtToken < _underlyingOfCollatToken` means `_debtToken` is token0
      _debtToken < _underlyingOfCollatToken ? _amount0 : _amount1,
      _path
    );

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan. will revert underflow if unprofitable
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, _amounts[0]);
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
  }

  function _computeV2PoolAddress(address _tokenA, address _tokenB) internal pure returns (address _poolAddress) {
    if (_tokenA > _tokenB) (_tokenA, _tokenB) = (_tokenB, _tokenA);
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex"ff",
                PANCAKE_V2_FACTORY,
                keccak256(abi.encodePacked(_tokenA, _tokenB)),
                PANCAKE_V2_POOL_INIT_CODE_HASH
              )
            )
          )
        )
      );
  }

  function _decodeV2Data(bytes memory _data)
    internal
    pure
    returns (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount
    )
  {
    return abi.decode(_data, (address, uint256, address, address, address, uint256));
  }

  // ==============
  // Pancakeswap V3
  // ==============

  function pancakeV3SingleHopFlashSwapRepurchase(bytes calldata _data) external {
    (
      ,
      ,
      address _debtToken,
      address _underlyingOfCollatToken,
      ,
      uint256 _desiredRepayAmount,
      uint24 _fee
    ) = _decodeV3Data(_data);

    address _poolAddress = _computeV3PoolAddress(_debtToken, _underlyingOfCollatToken, _fee);

    // exact input swap from underlyingOfCollat to debt aka flashloan debt, repurchase and repay underlyingOfCollat
    if (_debtToken < _underlyingOfCollatToken) {
      // debtToken is token0, underlyingOfCollatToken is token1
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        false, // swap token1 to token0
        -int256(_desiredRepayAmount),
        MAX_SQRTX96_PRICE, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = false`
        _data
      );
    } else {
      // debtToken is token1, underlyingOfCollatToken is token0
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        true, // swap token0 to token1
        int256(_desiredRepayAmount),
        MIN_SQRTX96_PRICE, // simulate SwapRouter's when `sqrtPriceLimitX96 = 0, zeroForOne = true`
        _data
      );
    }
  }

  function pancakeV3SwapCallback(
    int256 _amount0Delta,
    int256 _amount1Delta,
    bytes calldata _data
  ) external override {
    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken,
      address _collatToken,
      uint256 _desiredRepayAmount,
      uint24 _fee
    ) = _decodeV3Data(_data);

    // verify `msg.sender` is pool
    address _pool = _computeV3PoolAddress(_debtToken, _underlyingOfCollatToken, _fee);
    if (msg.sender != _pool) revert FlashLoanRepurchaser_BadPool();

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan on positve amountDelta side. only one side can be positive.
    IERC20(_underlyingOfCollatToken).safeTransfer(
      msg.sender,
      uint256(_amount0Delta > 0 ? _amount0Delta : _amount1Delta)
    );
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
  }

  function _computeV3PoolAddress(
    address _tokenA,
    address _tokenB,
    uint24 _fee
  ) internal pure returns (address _poolAddress) {
    if (_tokenA > _tokenB) (_tokenA, _tokenB) = (_tokenB, _tokenA);
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex"ff",
                PANCAKE_V3_POOL_DEPLOYER,
                keccak256(abi.encode(_tokenA, _tokenB, _fee)),
                PANCAKE_V3_POOL_INIT_CODE_HASH
              )
            )
          )
        )
      );
  }

  function _decodeV3Data(bytes memory _data)
    internal
    pure
    returns (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount,
      uint24 _flashloanFee
    )
  {
    return abi.decode(_data, (address, uint256, address, address, address, uint256, uint24));
  }
}
