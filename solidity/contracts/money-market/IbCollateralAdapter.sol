// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibShareUtil } from "./libraries/LibShareUtil.sol";
import { LibSafeToken } from "./libraries/LibSafeToken.sol";
import { LibMoneyMarket01 } from "./libraries/LibMoneyMarket01.sol";

// ---- Interfaces ---- //
import { ICollateralAdapter } from "./interfaces/ICollateralAdapter.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";
import { IWNativeRelayer } from "./interfaces/IWNativeRelayer.sol";
import { IAlpacaV2Oracle } from "./interfaces/IAlpacaV2Oracle.sol";

contract IbCollateralAdapter is ICollateralAdapter {
  using LibSafeToken for IERC20;

  error IbCollateralAdapter_InvalidIbToken(address _ibToken);

  IMoneyMarket private _moneyMarket;

  constructor(address moneyMarket_) {
    _moneyMarket = IMoneyMarket(moneyMarket_);
    // sanity check
    _moneyMarket.getOracle();
  }

  modifier validateIbToken(address _ibToken) {
    address _underlyingToken = _moneyMarket.getTokenFromIbToken(_ibToken);
    if (_underlyingToken == address(0)) {
      revert IbCollateralAdapter_InvalidIbToken(_ibToken);
    }
    _;
  }

  function getTokenConfig(address _ibToken)
    external
    view
    validateIbToken(_ibToken)
    returns (LibMoneyMarket01.TokenConfig memory _tokenConfig)
  {
    address _underlyingToken = _moneyMarket.getTokenFromIbToken(_ibToken);
    _tokenConfig = _moneyMarket.getTokenConfig(_underlyingToken);
  }

  function getPrice(address _ibToken) external view validateIbToken(_ibToken) returns (uint256 _price) {
    address _underlyingToken = _moneyMarket.getTokenFromIbToken(_ibToken);
    IAlpacaV2Oracle _oracle = _moneyMarket.getOracle();

    uint256 _underlyingTokenPrice;
    (_underlyingTokenPrice, ) = _oracle.getTokenPrice(_underlyingToken);

    uint256 _totalSupply = IERC20(_ibToken).totalSupply();
    uint256 _totalToken = _moneyMarket.getTotalTokenWithPendingInterest(_underlyingToken);

    _price = LibShareUtil.shareToValue(_underlyingTokenPrice, _totalToken, _totalSupply);
  }

  function unwrap(
    address _ibNativeToken,
    address _nativeRelayer,
    address _to,
    uint256 _amount
  ) external {
    address _nativeToken = _moneyMarket.getTokenFromIbToken(_ibNativeToken);
    if (_nativeToken == address(0)) {
      revert IbCollateralAdapter_InvalidIbToken(_ibNativeToken);
    }

    IERC20(_nativeToken).safeTransfer(_nativeRelayer, _amount);
    IWNativeRelayer(_nativeRelayer).withdraw(_amount);
    LibSafeToken.safeTransferETH(_to, _amount);
  }
}
