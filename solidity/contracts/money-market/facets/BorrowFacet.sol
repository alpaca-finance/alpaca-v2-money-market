// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { IBorrowFacet } from "../interfaces/IBorrowFacet.sol";

contract BorrowFacet is IBorrowFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using SafeCast for uint256;

  event LogRemoveDebt(
    address indexed _subAccount,
    address indexed _token,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogRepay(address indexed _user, uint256 indexed _subAccountId, address _token, uint256 _actualRepayAmount);
  event LogRepayWithCollat(
    address indexed _user,
    uint256 indexed _subAccountId,
    address _token,
    uint256 _actualRepayAmount
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function borrow(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(msg.sender, _subAccountId);
    // interest must accrue first
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    _validate(_subAccount, _token, _amount, moneyMarketDs);

    LibDoublyLinkedList.List storage userDebtShare = moneyMarketDs.subAccountDebtShares[_subAccount];

    if (userDebtShare.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      userDebtShare.init();
    }

    uint256 _globalDebtShare = moneyMarketDs.debtShares[_token];
    uint256 _globalDebtValue = moneyMarketDs.debtValues[_token];

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(_amount, _globalDebtShare, _globalDebtValue);

    // update over collat debt
    moneyMarketDs.debtShares[_token] += _shareToAdd;
    moneyMarketDs.debtValues[_token] += _amount;

    // update global debt
    moneyMarketDs.globalDebts[_token] += _amount;

    uint256 _newShareAmount = userDebtShare.getAmount(_token) + _shareToAdd;

    // update user's debtshare
    userDebtShare.addOrUpdate(_token, _newShareAmount);

    ERC20(_token).safeTransfer(msg.sender, _amount);
  }

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _debtShareToRepay
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (uint256 _oldSubAccountDebtShare, ) = _getDebt(_subAccount, _token, moneyMarketDs);

    uint256 _actualShareToRepay = Math.min(_oldSubAccountDebtShare, _debtShareToRepay);

    uint256 _actualRepayAmount = _removeDebt(
      _subAccount,
      _token,
      _oldSubAccountDebtShare,
      _actualShareToRepay,
      moneyMarketDs
    );

    // transfer only amount to repay
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);

    emit LogRepay(_account, _subAccountId, _token, _actualRepayAmount);
  }

  function repayWithCollat(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);
    LibMoneyMarket01.accrueBorrowedPositionsOf(_subAccount, moneyMarketDs);

    // actual repay amount is minimum of collateral amount, debt amount, and repay amount
    uint256 _collateralAmount = moneyMarketDs.subAccountCollats[_subAccount].getAmount(_token);

    (uint256 _oldSubAccountDebtShare, uint256 _oldDebtAmount) = _getDebt(_subAccount, _token, moneyMarketDs);

    uint256 _maximumAmountToRemove = _collateralAmount > _oldDebtAmount ? _oldDebtAmount : _collateralAmount;

    uint256 _amountToRemove = _repayAmount > _maximumAmountToRemove ? _maximumAmountToRemove : _repayAmount;

    uint256 _shareToRemove = LibShareUtil.valueToShare(
      _amountToRemove,
      moneyMarketDs.debtShares[_token],
      moneyMarketDs.debtValues[_token]
    );

    uint256 _actualRepayAmount = _removeDebt(
      _subAccount,
      _token,
      _oldSubAccountDebtShare,
      _shareToRemove,
      moneyMarketDs
    );

    if (_actualRepayAmount > _collateralAmount) {
      revert BorrowFacet_TooManyCollateralRemoved();
    }

    moneyMarketDs.subAccountCollats[_subAccount].updateOrRemove(_token, _collateralAmount - _actualRepayAmount);
    moneyMarketDs.collats[_token] -= _actualRepayAmount;

    emit LogRepayWithCollat(_account, _subAccountId, _token, _actualRepayAmount);
  }

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountDebtShares = moneyMarketDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) public view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_debtShare, _debtAmount) = _getDebt(_subAccount, _token, moneyMarketDs);
  }

  function _getDebt(
    address _subAccount,
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _debtShare, uint256 _debtAmount) {
    _debtShare = moneyMarketDs.subAccountDebtShares[_subAccount].getAmount(_token);

    // Note: precision loss 1 wei when convert share back to value
    _debtAmount = LibShareUtil.shareToValue(
      _debtShare,
      moneyMarketDs.debtValues[_token],
      moneyMarketDs.debtShares[_token]
    );
  }

  function getGlobalDebt(address _token) external view returns (uint256, uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return (moneyMarketDs.debtShares[_token], moneyMarketDs.debtValues[_token]);
  }

  function _removeDebt(
    address _subAccount,
    address _token,
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRemove,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal returns (uint256 _repayAmount) {
    uint256 _oldDebtShare = moneyMarketDs.debtShares[_token];
    uint256 _oldDebtValue = moneyMarketDs.debtValues[_token];

    // update user debtShare
    moneyMarketDs.subAccountDebtShares[_subAccount].updateOrRemove(_token, _oldSubAccountDebtShare - _shareToRemove);

    // update over collat debtShare
    _repayAmount = LibShareUtil.shareToValue(_shareToRemove, _oldDebtValue, _oldDebtShare);

    moneyMarketDs.debtShares[_token] -= _shareToRemove;
    moneyMarketDs.debtValues[_token] -= _repayAmount;

    // update global debt

    moneyMarketDs.globalDebts[_token] -= _repayAmount;

    // emit event
    emit LogRemoveDebt(_subAccount, _token, _shareToRemove, _repayAmount);
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
    uint256 _totalBorrowingPower = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);

    (uint256 _totalUsedBorrowedPower, bool _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowedPower(
      _subAccount,
      moneyMarketDs
    );

    if (moneyMarketDs.tokenConfigs[_token].tier == LibMoneyMarket01.AssetTier.ISOLATE) {
      if (
        !moneyMarketDs.subAccountDebtShares[_subAccount].has(_token) &&
        moneyMarketDs.subAccountDebtShares[_subAccount].size > 0
      ) {
        revert BorrowFacet_InvalidAssetTier();
      }
    } else if (_hasIsolateAsset) {
      revert BorrowFacet_InvalidAssetTier();
    }

    _checkBorrowingPower(_totalBorrowingPower, _totalUsedBorrowedPower, _token, _amount, moneyMarketDs);

    _checkAvailableToken(_token, _amount, moneyMarketDs);
  }

  // TODO: gas optimize on oracle call
  function _checkBorrowingPower(
    uint256 _borrowingPower,
    uint256 _borrowedValue,
    address _token,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    (uint256 _tokenPrice, ) = LibMoneyMarket01.getPriceUSD(_token, moneyMarketDs);

    LibMoneyMarket01.TokenConfig memory _tokenConfig = moneyMarketDs.tokenConfigs[_token];

    uint256 _borrowingUSDValue = LibMoneyMarket01.usedBorrowedPower(
      _amount * _tokenConfig.to18ConversionFactor,
      _tokenPrice,
      _tokenConfig.borrowingFactor
    );

    if (_borrowingPower < _borrowedValue + _borrowingUSDValue) {
      revert BorrowFacet_BorrowingValueTooHigh(_borrowingPower, _borrowedValue, _borrowingUSDValue);
    }
  }

  function _checkAvailableToken(
    address _token,
    uint256 _borrowAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) - moneyMarketDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
      revert BorrowFacet_NotEnoughToken(_borrowAmount);
    }

    if (_borrowAmount + moneyMarketDs.debtValues[_token] > moneyMarketDs.tokenConfigs[_token].maxBorrow) {
      revert BorrowFacet_ExceedBorrowLimit();
    }
  }

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPowerUSDValue = LibMoneyMarket01.getTotalBorrowingPower(_subAccount, moneyMarketDs);
  }

  function getTotalUsedBorrowedPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _subAccount = LibMoneyMarket01.getSubAccount(_account, _subAccountId);

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibMoneyMarket01.getTotalUsedBorrowedPower(_subAccount, moneyMarketDs);
  }

  function debtLastAccrueTime(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtLastAccrueTime[_token];
  }

  function pendingInterest(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.pendingInterest(_token, moneyMarketDs);
  }

  function accrueInterest(address _token) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);
  }

  function debtValues(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtValues[_token];
  }

  function getFloatingBalance(address _token) external view returns (uint256 _floating) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _floating = LibMoneyMarket01.getFloatingBalance(_token, moneyMarketDs);
  }

  function debtShares(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtShares[_token];
  }
}
