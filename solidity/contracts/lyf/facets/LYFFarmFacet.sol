// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";

// interfaces
import { ILYFFarmFacet } from "../interfaces/ILYFFarmFacet.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";

contract LYFFarmFacet is ILYFFarmFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogRemoveDebt(
    address indexed _subAccount,
    address indexed _token,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogRepay(address indexed _user, uint256 indexed _subAccountId, address _token, uint256 _actualRepayAmount);

  function addFarmPosition(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _desireToken0Amount,
    uint256 _desireToken1Amount,
    uint256 _minLpReceive,
    address _addStrat
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subaccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    // 1. check subaccount collat
    uint256 _token0AmountFromCollat = _removeCollat(_subaccount, _token0, _desireToken0Amount, lyfDs);
    uint256 _token1AmountFromCollat = _removeCollat(_subaccount, _token1, _desireToken1Amount, lyfDs);

    /* borrow from mm 
    if (_token0AmountFromCollat < _desireToken0Amount) {
      _pullFunds();
    }

    if (_token1AmountFromCollat < _desireToken1Amount) {
      _pullFunds();
    }
    */

    // 3. send token to strat

    ERC20(_token0).safeTransfer(_addStrat, _token0AmountFromCollat);
    ERC20(_token1).safeTransfer(_addStrat, _token1AmountFromCollat);

    // 4. compose lp
    uint256 _lpReceived = IStrat(_addStrat).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _token0AmountFromCollat,
      _token1AmountFromCollat,
      _minLpReceive
    );

    LibLYF01.addCollat(_subaccount, _lpToken, _lpReceived, lyfDs);

    // 5. add it to collateral
    // 6. health check on sub account
  }

  function _removeCollat(
    address _subaccount,
    address _token,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _actualAmountRemove) {
    LibDoublyLinkedList.List storage _subAccountCollatList = lyfDs.subAccountCollats[_subaccount];
    uint256 _currentAmount = _subAccountCollatList.getAmount(_token);
    if (_currentAmount > 0) {
      _actualAmountRemove = _currentAmount > _amount ? _amount : _currentAmount;
      _subAccountCollatList.updateOrRemove(_token, _currentAmount - _actualAmountRemove);

      // update global collat
      lyfDs.collats[_token] -= _actualAmountRemove;
    }
  }

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _repayAmount
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // LibLYF01.accureInterest(_token, lyfDs);

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    (uint256 _oldSubAccountDebtShare, ) = _getDebt(_subAccount, _token, lyfDs);

    uint256 _shareToRemove = LibShareUtil.valueToShare(
      lyfDs.debtShares[_token],
      _repayAmount,
      lyfDs.debtValues[_token]
    );

    _shareToRemove = _oldSubAccountDebtShare > _shareToRemove ? _shareToRemove : _oldSubAccountDebtShare;

    uint256 _actualRepayAmount = _removeDebt(_subAccount, _token, _oldSubAccountDebtShare, _shareToRemove, lyfDs);

    // transfer only amount to repay
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);

    emit LogRepay(_account, _subAccountId, _token, _actualRepayAmount);
  }

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    LibDoublyLinkedList.List storage subAccountDebtShares = lyfDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token
  ) public view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    (_debtShare, _debtAmount) = _getDebt(_subAccount, _token, lyfDs);
  }

  function _getDebt(
    address _subAccount,
    address _token,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _debtShare, uint256 _debtAmount) {
    _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_token);

    // Note: precision loss 1 wei when convert share back to value
    _debtAmount = LibShareUtil.shareToValue(_debtShare, lyfDs.debtValues[_token], lyfDs.debtShares[_token]);
  }

  function getGlobalDebt(address _token) external view returns (uint256, uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    return (lyfDs.debtShares[_token], lyfDs.debtValues[_token]);
  }

  function _removeDebt(
    address _subAccount,
    address _token,
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRemove,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _repayAmount) {
    uint256 _oldDebtShare = lyfDs.debtShares[_token];
    uint256 _oldDebtValue = lyfDs.debtValues[_token];

    // update user debtShare
    lyfDs.subAccountDebtShares[_subAccount].updateOrRemove(_token, _oldSubAccountDebtShare - _shareToRemove);

    // update over collat debtShare
    _repayAmount = LibShareUtil.shareToValue(_shareToRemove, _oldDebtValue, _oldDebtShare);

    lyfDs.debtShares[_token] -= _shareToRemove;
    lyfDs.debtValues[_token] -= _repayAmount;

    // update global debt

    lyfDs.globalDebts[_token] -= _repayAmount;

    // emit event
    emit LogRemoveDebt(_subAccount, _token, _shareToRemove, _repayAmount);
  }

  function _validate(
    address _subAccount,
    address _token,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view {
    // todo: check if can borrow

    // check asset tier
    uint256 _totalBorrowingPower = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);

    (uint256 _totalUsedBorrowedPower, ) = LibLYF01.getTotalUsedBorrowedPower(_subAccount, lyfDs);

    _checkBorrowingPower(_totalBorrowingPower, _totalUsedBorrowedPower, _token, _amount, lyfDs);

    _checkAvailableToken(_token, _amount, lyfDs);
  }

  // TODO: handle token decimal when calculate value
  // TODO: gas optimize on oracle call
  function _checkBorrowingPower(
    uint256 _borrowingPower,
    uint256 _borrowedValue,
    address _token,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view {
    (uint256 _tokenPrice, ) = LibLYF01.getPriceUSD(_token, lyfDs);

    LibLYF01.TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_token];

    uint256 _borrowingUSDValue = LibLYF01.usedBorrowedPower(_amount, _tokenPrice, _tokenConfig.borrowingFactor);

    if (_borrowingPower < _borrowedValue + _borrowingUSDValue) {
      revert LYFFarmFacet_BorrowingValueTooHigh(_borrowingPower, _borrowedValue, _borrowingUSDValue);
    }
  }

  function _checkAvailableToken(
    address _token,
    uint256 _borrowAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) - lyfDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
      revert LYFFarmFacet_NotEnoughToken(_borrowAmount);
    }

    if (_borrowAmount + lyfDs.debtValues[_token] > lyfDs.tokenConfigs[_token].maxBorrow) {
      revert LYFFarmFacet_ExceedBorrowLimit();
    }
  }

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPowerUSDValue = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
  }

  function getTotalUsedBorrowedPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue, bool _hasIsolateAsset)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    (_totalBorrowedUSDValue, _hasIsolateAsset) = LibLYF01.getTotalUsedBorrowedPower(_subAccount, lyfDs);
  }

  function debtLastAccureTime(address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtLastAccureTime[_token];
  }

  function pendingInterest(address _token) public view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return LibLYF01.pendingInterest(_token, lyfDs);
  }

  function accureInterest(address _token) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    LibLYF01.accureInterest(_token, lyfDs);
  }

  function debtValues(address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtValues[_token];
  }

  function debtShares(address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.debtShares[_token];
  }
}
