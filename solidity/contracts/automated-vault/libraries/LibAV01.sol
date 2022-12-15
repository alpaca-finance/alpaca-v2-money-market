// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";

library LibAV01 {
  using SafeERC20 for ERC20;

  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  enum AssetTier {
    UNLISTED,
    COLLATERAL,
    LP
  }

  struct VaultConfig {
    address shareToken;
    address lpToken;
    address stableToken;
    address assetToken;
  }

  struct AVDiamondStorage {
    address moneyMarket;
    IAlpacaV2Oracle oracle;
    mapping(address => VaultConfig) vaultConfigs;
    mapping(address => uint256) vaultDebtShares;
    mapping(address => uint256) vaultDebtValues;
    mapping(address => TokenConfig) tokenConfigs;
  }

  struct TokenConfig {
    AssetTier tier;
    uint8 to18ConversionFactor;
    uint256 maxToleranceExpiredSecond;
  }

  error LibAV01_NoTinyShares();
  error LibAV01_TooLittleReceived();
  error LibAV01_PriceStale(address _token);
  error LibAV01_UnsupportedDecimals();

  function getStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }

  function getPriceUSD(address _token, AVDiamondStorage storage avDs)
    internal
    view
    returns (uint256 _price, uint256 _lastUpdated)
  {
    if (avDs.tokenConfigs[_token].tier == AssetTier.LP) {
      (_price, _lastUpdated) = avDs.oracle.lpToDollar(1e18, _token);
    } else {
      (_price, _lastUpdated) = avDs.oracle.getTokenPrice(_token);
    }
    if (_lastUpdated < block.timestamp - avDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibAV01_PriceStale(_token);
  }

  function deposit(
    address _shareToken,
    address _token,
    uint256 _amountIn,
    uint256 _minShareOut
  ) internal {
    uint256 _totalShareTokenSupply = ERC20(_shareToken).totalSupply();
    // TODO: replace _amountIn getTotalToken by equity
    uint256 _totalToken = _amountIn;

    uint256 _shareToMint = LibShareUtil.valueToShare(_amountIn, _totalShareTokenSupply, _totalToken);
    if (_minShareOut > _shareToMint) {
      revert LibAV01_TooLittleReceived();
    }
    if (_totalShareTokenSupply + _shareToMint < 10**(ERC20(_shareToken).decimals()) - 1) {
      revert LibAV01_NoTinyShares();
    }

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
    IAVShareToken(_shareToken).mint(msg.sender, _shareToMint);
  }

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut,
    AVDiamondStorage storage avDs
  ) internal {
    VaultConfig memory vaultConfig = avDs.vaultConfigs[_shareToken];

    // TODO: calculate amountOut with equity value
    // TODO: handle slippage

    IAVShareToken(_shareToken).burn(msg.sender, _shareAmountIn);
    ERC20(vaultConfig.stableToken).safeTransferFrom(msg.sender, address(this), _minTokenOut);
  }

  function to18ConversionFactor(address _token) internal view returns (uint8) {
    uint256 _decimals = ERC20(_token).decimals();
    if (_decimals > 18) revert LibAV01_UnsupportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint8(_conversionFactor);
  }
}
