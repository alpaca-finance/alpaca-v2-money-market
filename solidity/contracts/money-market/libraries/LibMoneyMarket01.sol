// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";

library LibMoneyMarket01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // keccak256("moneymarket.diamond.storage");
  bytes32 internal constant MONEY_MARKET_STORAGE_POSITION =
    0x2758c6926500ec9dc8ab8cea4053d172d4f50d9b78a6c2ee56aa5dd18d2c800b;

  uint256 internal constant MAX_BPS = 10000;

  error LibMoneyMarket01_BadSubAccountId();

  enum AssetTier {
    UNLISTED,
    ISOLATE,
    CROSS,
    COLLATERAL
  }

  struct TokenConfig {
    LibMoneyMarket01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
  }

  // Storage
  struct MoneyMarketDiamondStorage {
    mapping(address => address) tokenToIbTokens;
    mapping(address => address) ibTokenToTokens;
    mapping(address => uint256) debtValues;
    mapping(address => uint256) debtShares;
    mapping(address => uint256) collats;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares;
    // account -> list token debt
    mapping(address => LibDoublyLinkedList.List) nonCollatAccountDebtValues;
    // token -> debt of each account
    mapping(address => LibDoublyLinkedList.List) nonCollatTokenDebtValues;
    mapping(address => TokenConfig) tokenConfigs;
    address oracle;
  }

  function moneyMarketDiamondStorage()
    internal
    pure
    returns (MoneyMarketDiamondStorage storage moneyMarketStorage)
  {
    assembly {
      moneyMarketStorage.slot := MONEY_MARKET_STORAGE_POSITION
    }
  }

  function getSubAccount(address primary, uint256 subAccountId)
    internal
    pure
    returns (address)
  {
    if (subAccountId > 255) revert LibMoneyMarket01_BadSubAccountId();
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  // TODO: handle decimal
  function getTotalBorrowingPower(
    address _subAccount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _totalBorrowingPowerUSDValue) {
    LibDoublyLinkedList.Node[] memory _collats = moneyMarketDs
      .subAccountCollats[_subAccount]
      .getAll();

    uint256 _collatsLength = _collats.length;

    for (uint256 _i = 0; _i < _collatsLength; ) {
      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[
        _collats[_i].token
      ];

      // TODO: get tokenPrice from oracle
      uint256 _tokenPrice = 1e18;

      // _totalBorrowingPowerUSDValue += amount * tokenPrice * collateralFactor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _collats[_i].amount * _tokenConfig.collateralFactor,
        _tokenPrice,
        1e22
      );

      unchecked {
        _i++;
      }
    }
  }

  function getNonCollatGlobalDebt(
    address _token,
    MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _totalNonCollatDebt) {
    LibDoublyLinkedList.Node[] memory _nonCollatDebts = moneyMarketDs
      .nonCollatTokenDebtValues[_token]
      .getAll();

    uint256 _length = _nonCollatDebts.length;

    for (uint256 _i = 0; _i < _length; ) {
      _totalNonCollatDebt += _nonCollatDebts[_i].amount;

      unchecked {
        _i++;
      }
    }
  }

  function getTotalUsedBorrowedPower(
    address _subAccount,
    MoneyMarketDiamondStorage storage moneyMarketDs
  )
    internal
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibDoublyLinkedList.Node[] memory _borrowed = moneyMarketDs
      .subAccountDebtShares[_subAccount]
      .getAll();

    uint256 _borrowedLength = _borrowed.length;

    for (uint256 _i = 0; _i < _borrowedLength; ) {
      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[
        _borrowed[_i].token
      ];

      if (_tokenConfig.tier == LibMoneyMarket01.AssetTier.ISOLATE) {
        _hasIsolateAsset = true;
      }
      // TODO: get tokenPrice from oracle
      uint256 _tokenPrice = 1e18;
      uint256 _borrowedAmount = LibShareUtil.shareToValue(
        moneyMarketDs.debtShares[_borrowed[_i].token],
        _borrowed[_i].amount,
        moneyMarketDs.debtValues[_borrowed[_i].token]
      );

      // _totalBorrowedUSDValue += _borrowedAmount * tokenPrice * (10000+ borrowingFactor)
      _totalBorrowedUSDValue += LibFullMath.mulDiv(
        _borrowedAmount * (MAX_BPS + _tokenConfig.borrowingFactor),
        _tokenPrice,
        1e22
      );

      unchecked {
        _i++;
      }
    }
  }
}
