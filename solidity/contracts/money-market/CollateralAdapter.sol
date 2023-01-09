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
import { IAlpacaV2Oracle } from "./interfaces/IAlpacaV2Oracle.sol";
import { IWNativeRelayer } from "./interfaces/IWNativeRelayer.sol";

contract CollateralAdapter is ICollateralAdapter {
  using LibSafeToken for IERC20;

  IMoneyMarket private _moneyMarket;

  constructor(address moneyMarket_) {
    _moneyMarket = IMoneyMarket(moneyMarket_);
    // sanity check
    _moneyMarket.getOracle();
  }

  function getTokenConfig(address _token) external view returns (LibMoneyMarket01.TokenConfig memory _tokenConfig) {
    _tokenConfig = _moneyMarket.getTokenConfig(_token);
  }

  function getPrice(address _token) external view returns (uint256 _price) {
    (_price, ) = _moneyMarket.getOracle().getTokenPrice(_token);
  }

  function unwrap(
    address _nativeToken,
    address _nativeRelayer,
    address _to,
    uint256 _amount
  ) external {
    IERC20(_nativeToken).safeTransfer(_nativeRelayer, _amount);
    IWNativeRelayer(_nativeRelayer).withdraw(_amount);
    LibSafeToken.safeTransferETH(_to, _amount);
  }
}
