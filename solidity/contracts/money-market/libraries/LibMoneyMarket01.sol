// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IIbToken } from "../interfaces/IIbToken.sol";

// interfaces
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

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
    mapping(address => bool) nonCollatBorrowerOk;
    mapping(address => TokenConfig) tokenConfigs;
    address oracle;
    mapping(address => uint256) debtLastAccureTime;
    mapping(address => IInterestRateModel) interestModels;
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
      address _collatToken = _collats[_i].token;
      uint256 _collatAmount = _collats[_i].amount;
      uint256 _actualAmount = _collatAmount;

      // will return address(0) if _collatToken is not ibToken
      address _actualToken = moneyMarketDs.ibTokenToTokens[_collatToken];
      if (_actualToken == address(0)) {
        _actualToken = _collatToken;
      } else {
        uint256 _totalSupply = IIbToken(_collatToken).totalSupply();
        uint256 _totalToken = getTotalToken(_actualToken, moneyMarketDs);

        _actualAmount = LibShareUtil.shareToValue(
          _collatAmount,
          _totalToken,
          _totalSupply
        );
      }

      TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[
        _actualToken
      ];

      // TODO: get tokenPrice from oracle
      uint256 _tokenPrice = 1e18;

      // _totalBorrowingPowerUSDValue += amount * tokenPrice * collateralFactor
      _totalBorrowingPowerUSDValue += LibFullMath.mulDiv(
        _actualAmount * _tokenConfig.collateralFactor,
        _tokenPrice,
        1e22
      );

      unchecked {
        _i++;
      }
    }
  }

  function getNonCollatTokenDebt(
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
        _borrowed[_i].amount,
        moneyMarketDs.debtValues[_borrowed[_i].token],
        moneyMarketDs.debtShares[_borrowed[_i].token]
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

  function pendingIntest(
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256) {
    uint256 _lastAccureTime = moneyMarketDs.debtLastAccureTime[_token];

    if (block.timestamp > _lastAccureTime) {
      uint256 _timePast = block.timestamp - _lastAccureTime;
      // uint256 balance = ERC20(_token).balanceOf(address(this));
      if (address(moneyMarketDs.interestModels[_token]) == address(0)) {
        return 0;
      }

      uint256 _interestRate = IInterestRateModel(
        moneyMarketDs.interestModels[_token]
      ).getInterestRate(moneyMarketDs.debtValues[_token], 0);

      // TODO: change it when dynamically comes
      return _interestRate * _timePast;
      // return ratePerSec.mul(vaultDebtVal).mul(timePast).div(1e18);
    } else {
      return 0;
    }
  }

  function accureInterest(
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    if (block.timestamp > moneyMarketDs.debtLastAccureTime[_token]) {
      uint256 _interest = pendingIntest(_token, moneyMarketDs);
      // uint256 toReserve = interest.mul(moneyMarketDs.getReservePoolBps()).div(
      //   10000
      // );
      // reservePool = reservePool.add(toReserve);

      moneyMarketDs.debtValues[_token] += _interest;
      moneyMarketDs.debtLastAccureTime[_token] = block.timestamp;
    }
  }

  // totalToken is the amount of token remains in MM + borrowed amount - collateral from user
  // where borrowed amount consists of over-collat and non-collat borrowing
  function getTotalToken(
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256) {
    // TODO: optimize this by using global state var
    uint256 _nonCollatDebt = getNonCollatTokenDebt(_token, moneyMarketDs);
    return
      (ERC20(_token).balanceOf(address(this)) +
        moneyMarketDs.debtValues[_token] +
        _nonCollatDebt) - moneyMarketDs.collats[_token];
  }

  function setIbPair(
    address _token,
    address _ibToken,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    moneyMarketDs.tokenToIbTokens[_token] = _ibToken;
    moneyMarketDs.ibTokenToTokens[_ibToken] = _token;
  }

  function setTokenConfig(
    address _token,
    TokenConfig memory _config,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    moneyMarketDs.tokenConfigs[_token] = _config;
  }
}
