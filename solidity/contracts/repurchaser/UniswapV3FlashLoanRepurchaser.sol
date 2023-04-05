// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "./interfaces/IUniswapV3SwapCallback.sol";

import { LibSafeToken } from "./libraries/LibSafeToken.sol";

contract UniswapV3FlashLoanRepurchaser is IUniswapV3SwapCallback {
  using LibSafeToken for IERC20;

  error UniswapV3FlashLoanRepurchaser_Unauthorized();
  error UniswapV3FlashLoanRepurchaser_BadPool();

  address constant UNISWAP_V3_FACTORY = 0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7;
  bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
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
    if (msg.sender != owner) revert UniswapV3FlashLoanRepurchaser_Unauthorized();
    IERC20(_token).safeTransfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  function initRepurchase(bytes calldata _data) external {
    (
      ,
      ,
      address _debtToken,
      address _underlyingOfCollatToken,
      ,
      uint24 _fee,
      uint256 _desiredRepayAmount
    ) = _decodeData(_data);

    address _poolAddress = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _fee);

    // exact input swap from underlyingOfCollat to debt aka flashloan debt, repurchase and repay underlyingOfCollat
    if (_debtToken < _underlyingOfCollatToken) {
      // debtToken is token0, underlyingOfCollatToken is token1
      IUniswapV3Pool(_poolAddress).swap(
        address(this),
        false, // swap token1 to token0
        int256(_desiredRepayAmount),
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

  function uniswapV3SwapCallback(
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
      uint24 _flashloanFee,
      uint256 _desiredRepayAmount
    ) = _decodeData(_data);

    // verify `msg.sender` is pool
    address _pool = _computePoolAddress(_debtToken, _underlyingOfCollatToken, _flashloanFee);
    if (msg.sender != _pool) revert UniswapV3FlashLoanRepurchaser_BadPool();

    _repurchaseAndWithdrawIb(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan on positve amountDelta side. only one side can be positive.
    IERC20(_underlyingOfCollatToken).safeTransfer(
      msg.sender,
      uint256(_amount0Delta > 0 ? _amount0Delta : _amount1Delta)
    );
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
                UNISWAP_V3_FACTORY,
                keccak256(abi.encode(_tokenA, _tokenB, _fee)),
                POOL_INIT_CODE_HASH
              )
            )
          )
        )
      );
  }

  function _decodeData(bytes memory _data)
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
    return abi.decode(_data, (address, uint256, address, address, address, uint24, uint256));
  }
}
