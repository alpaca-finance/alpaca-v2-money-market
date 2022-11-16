// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// libs
import { LibDoublyLinkedList } from "./LibDoublyLinkedList.sol";
import { LibFullMath } from "./LibFullMath.sol";
import { LibShareUtil } from "./LibShareUtil.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";

library LibLYF01 {
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  // keccak256("lyf.diamond.storage");
  bytes32 internal constant LYF_STORAGE_POSITION = 0x23ec0f04376c11672050f8fa65aa7cdd1b6edcb0149eaae973a7060e7ef8f3f4;

  uint256 internal constant MAX_BPS = 10000;

  error LibLYF01_BadSubAccountId();
  error LibLYF01_PriceStale(address);

  enum AssetTier {
    UNLISTED,
    ISOLATE,
    CROSS,
    COLLATERAL
  }

  struct TokenConfig {
    LibLYF01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
    uint256 maxToleranceExpiredSecond;
  }

  // Storage
  struct LYFDiamondStorage {
    IPriceOracle oracle;
    mapping(address => uint256) collats;
    mapping(address => LibDoublyLinkedList.List) subAccountCollats;
    mapping(address => TokenConfig) tokenConfigs;
    mapping(address => LibDoublyLinkedList.List) subAccountDebtShares;
    mapping(address => uint256) debtShares;
    mapping(address => uint256) debtValues;
    mapping(address => uint256) globalDebts;
    mapping(address => uint256) debtLastAccureTime;
  }

  function lyfDiamondStorage() internal pure returns (LYFDiamondStorage storage lyfStorage) {
    assembly {
      lyfStorage.slot := LYF_STORAGE_POSITION
    }
  }

  function getSubAccount(address primary, uint256 subAccountId) internal pure returns (address) {
    if (subAccountId > 255) revert LibLYF01_BadSubAccountId();
    return address(uint160(primary) ^ uint160(subAccountId));
  }

  function setTokenConfig(
    address _token,
    TokenConfig memory _config,
    LYFDiamondStorage storage lyfDs
  ) internal {
    lyfDs.tokenConfigs[_token] = _config;
  }

  function pendingInterest(address _token, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _pendingInterest)
  {}

  function accureInterest(address _token, LYFDiamondStorage storage lyfDs) internal {}

  // TODO: handle decimal
  function getTotalBorrowingPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibDoublyLinkedList.Node[] memory _collats = lyfDs.subAccountCollats[_subAccount].getAll();

    uint256 _collatsLength = _collats.length;

    for (uint256 _i = 0; _i < _collatsLength; ) {
      address _collatToken = _collats[_i].token;
      uint256 _collatAmount = _collats[_i].amount;
      uint256 _actualAmount = _collatAmount;

      // todo: support ibToken?
      // will return address(0) if _collatToken is not ibToken
      // address _actualToken = lyfDs.ibTokenToTokens[_collatToken];
      // if (_actualToken == address(0)) {
      //   _actualToken = _collatToken;
      // } else {
      //   uint256 _totalSupply = IIbToken(_collatToken).totalSupply();
      //   uint256 _totalToken = getTotalToken(_actualToken, lyfDs);

      //   _actualAmount = LibShareUtil.shareToValue(_collatAmount, _totalToken, _totalSupply);
      // }

      TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_collatToken];

      (uint256 _tokenPrice, ) = getPriceUSD(_collatToken, lyfDs);

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

  function getTotalUsedBorrowedPower(address _subAccount, LYFDiamondStorage storage lyfDs)
    internal
    view
    returns (uint256 _totalUsedBorrowedPower, bool _hasIsolateAsset)
  {
    // todo: debt thing
    // LibDoublyLinkedList.Node[] memory _borrowed = lyfDs.subAccountDebtShares[_subAccount].getAll();
    // uint256 _borrowedLength = _borrowed.length;
    // for (uint256 _i = 0; _i < _borrowedLength; ) {
    //   TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_borrowed[_i].token];
    //   if (_tokenConfig.tier == AssetTier.ISOLATE) {
    //     _hasIsolateAsset = true;
    //   }
    //   (uint256 _tokenPrice, ) = getPriceUSD(_borrowed[_i].token, lyfDs);
    //   uint256 _borrowedAmount = LibShareUtil.shareToValue(
    //     _borrowed[_i].amount,
    //     lyfDs.debtValues[_borrowed[_i].token],
    //     lyfDs.debtShares[_borrowed[_i].token]
    //   );
    //   _totalUsedBorrowedPower += usedBorrowedPower(_borrowedAmount, _tokenPrice, _tokenConfig.borrowingFactor);
    //   unchecked {
    //     _i++;
    //   }
    // }
  }

  function getPriceUSD(address _token, LYFDiamondStorage storage lyfDs) internal view returns (uint256, uint256) {
    (uint256 _price, uint256 _lastUpdated) = lyfDs.oracle.getPrice(
      _token,
      address(0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff)
    );
    if (_lastUpdated < block.timestamp - lyfDs.tokenConfigs[_token].maxToleranceExpiredSecond)
      revert LibLYF01_PriceStale(_token);
    return (_price, _lastUpdated);
  }

  // totalToken is the amount of token remains in MM + borrowed amount - collateral from user
  // where borrowed amount consists of over-collat and non-collat borrowing
  function getTotalToken(address _token, LYFDiamondStorage storage lyfDs) internal view returns (uint256) {
    // todo: think about debt
    // return (ERC20(_token).balanceOf(address(this)) + lyfDs.globalDebts[_token]) - lyfDs.collats[_token];
    return ERC20(_token).balanceOf(address(this)) - lyfDs.collats[_token];
  }

  // _usedBorrowedPower += _borrowedAmount * tokenPrice * (10000/ borrowingFactor)
  function usedBorrowedPower(
    uint256 _borrowedAmount,
    uint256 _tokenPrice,
    uint256 _borrowingFactor
  ) internal pure returns (uint256 _usedBorrowedPower) {
    _usedBorrowedPower = LibFullMath.mulDiv(_borrowedAmount * MAX_BPS, _tokenPrice, 1e18 * uint256(_borrowingFactor));
  }
}
