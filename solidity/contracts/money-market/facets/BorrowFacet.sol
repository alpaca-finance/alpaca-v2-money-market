// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";

// interfaces
import { IBorrowFacet } from "../interfaces/IBorrowFacet.sol";

contract BorrowFacet is IBorrowFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function borrow(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    _validate(_subAccount, _token, _amount, moneyMarketDs);

    LibDoublyLinkedList.List storage debtShare = moneyMarketDs
      .subAccountDebtShares[_subAccount];

    if (
      debtShare.getNextOf(LibDoublyLinkedList.START) ==
      LibDoublyLinkedList.EMPTY
    ) {
      debtShare.init();
    }

    uint256 _totalSupply = moneyMarketDs.debtShares[_token];
    uint256 _totalValue = moneyMarketDs.debtValues[_token];

    uint256 _shareToAdd = LibShareUtil.valueToShare(
      _totalSupply,
      _amount,
      _totalValue
    );

    moneyMarketDs.debtShares[_token] += _shareToAdd;
    moneyMarketDs.debtValues[_token] += _amount;

    uint256 _newAmount = debtShare.getAmount(_token) + _amount;
    // update user's debtshare
    debtShare.addOrUpdate(_token, _newAmount);

    ERC20(_token).safeTransfer(_account, _amount);
  }

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    LibDoublyLinkedList.List storage debtShares = moneyMarketDs
      .subAccountDebtShares[_subAccount];

    return debtShares.getAll();
  }

  function _validate(
    address _subAccount,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    // check open market
    if (_ibToken == address(0)) {
      revert BorrowFacet_InvalidToken(_token);
    }

    // check asset tier
    uint256 _totalBorrowingPowerUSDValue = LibMoneyMarket01
      .getTotalBorrowingPower(_subAccount, moneyMarketDs);

    (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset) = LibMoneyMarket01
      .getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);

    if (
      moneyMarketDs.tokenConfigs[_token].tier ==
      LibMoneyMarket01.AssetTier.ISOLATE
    ) {
      if (
        !moneyMarketDs.subAccountDebtShares[_subAccount].has(_token) &&
        moneyMarketDs.subAccountDebtShares[_subAccount].size > 0
      ) {
        revert BorrowFacet_InvalidAssetTier();
      }
    } else if (_hasIsolateAsset) {
      revert BorrowFacet_InvalidAssetTier();
    }

    _checkBorrowingPower(
      _totalBorrowingPowerUSDValue,
      _totalBorrowedUSDValue,
      _token,
      _amount,
      moneyMarketDs
    );

    _checkAvailableToken(_token, _amount, moneyMarketDs);
  }

  // TODO: handle token decimal when calculate value
  // TODO: gas optimize on oracle call
  function _checkBorrowingPower(
    uint256 _borrowingPower,
    uint256 _borrowedValue,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    // TODO: get tokenPrice from oracle
    uint256 _tokenPrice = 1e18;

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs
      .tokenConfigs[_token];

    uint256 _borrowingUSDValue = LibFullMath.mulDiv(
      _amount * (LibMoneyMarket01.MAX_BPS + _tokenConfig.borrowingFactor),
      _tokenPrice,
      1e22
    );

    if (_borrowingPower < _borrowedValue + _borrowingUSDValue) {
      revert BorrowFacet_BorrowingValueTooHigh(
        _borrowingPower,
        _borrowedValue,
        _borrowingUSDValue
      );
    }
  }

  function _checkAvailableToken(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) -
      moneyMarketDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
      revert BorrowFacet_NotEnoughToken(_borrowAmount);
    }
  }

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    _totalBorrowingPowerUSDValue = LibMoneyMarket01.getTotalBorrowingPower(
      _subAccount,
      moneyMarketDs
    );
  }

  function getTotalUsedBorrowedPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(
      _account,
      _subAccountId
    );

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibMoneyMarket01
      .getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);
  }
}
