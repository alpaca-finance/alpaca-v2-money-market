// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibFullMath } from "../libraries/LibFullMath.sol";

// interfaces
import { ILYFFarmFacet } from "../interfaces/ILYFFarmFacet.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";
import { IStrat } from "../interfaces/IStrat.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";

contract LYFFarmFacet is ILYFFarmFacet {
  using SafeERC20 for ERC20;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;

  error LYFFarmFacet_BorrowingPowerTooLow();

  event LogRemoveDebt(
    address indexed _subAccount,
    uint256 indexed _debtShareId,
    uint256 _removeDebtShare,
    uint256 _removeDebtAmount
  );

  event LogAddFarmPosition(address indexed _subAccount, address indexed _lpToken, uint256 _lpAmount);

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

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    LibLYF01.accureAllSubAccountDebtShares(_subAccount, lyfDs);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    LibLYF01.accureInterest(lyfDs.debtShareIds[_token0][_lpToken], lyfDs);
    LibLYF01.accureInterest(lyfDs.debtShareIds[_token1][_lpToken], lyfDs);

    // 1. check subaccount collat
    uint256 _token0AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token0, _desireToken0Amount, lyfDs);
    uint256 _token1AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token1, _desireToken1Amount, lyfDs);

    //2. borrow from mm if collats do not cover the desire amount
    _borrowFromMoneyMarket(_subAccount, _token0, _lpToken, _desireToken0Amount - _token0AmountFromCollat, lyfDs);
    _borrowFromMoneyMarket(_subAccount, _token1, _lpToken, _desireToken1Amount - _token1AmountFromCollat, lyfDs);

    // 3. send token to strat

    ERC20(_token0).safeTransfer(_addStrat, _desireToken0Amount);
    ERC20(_token1).safeTransfer(_addStrat, _desireToken1Amount);

    // 4. compose lp
    uint256 _lpReceived = IStrat(_addStrat).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _desireToken0Amount,
      _desireToken1Amount,
      _minLpReceive
    );

    // 5. add it to collateral
    LibLYF01.addCollat(_subAccount, _lpToken, _lpReceived, lyfDs);

    // 6. health check on sub account
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }
    emit LogAddFarmPosition(_subAccount, _lpToken, _lpReceived);
  }

  function liquidateLP(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount,
    address _removeStrat
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    if (lyfDs.tokenConfigs[_lpToken].tier != LibLYF01.AssetTier.LP) {
      revert LYFFarmFacet_InvalidAssetTier();
    }

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    LibLYF01.accureInterest(lyfDs.debtShareIds[_token0][_lpToken], lyfDs);
    LibLYF01.accureInterest(lyfDs.debtShareIds[_token1][_lpToken], lyfDs);

    // todo: handle slippage
    uint256 _lpFromCollatRemoval = LibLYF01.removeCollateral(_subAccount, _lpToken, _lpShareAmount, lyfDs);

    ERC20(_lpToken).safeTransfer(_removeStrat, _lpFromCollatRemoval);
    (uint256 _token0Return, uint256 _token1Return) = IStrat(_removeStrat).removeLiquidity(_lpToken);

    LibLYF01.addCollat(_subAccount, _token0, _token0Return, lyfDs);
    LibLYF01.addCollat(_subAccount, _token1, _token1Return, lyfDs);
  }

  function _borrowFromMoneyMarket(
    address _subAccount,
    address _token,
    address _lpToken,
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    if (_amount == 0) return;
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];

    IMoneyMarket(lyfDs.moneyMarket).nonCollatBorrow(_token, _amount);

    // update subaccount debt
    // todo: optimize this
    LibUIntDoublyLinkedList.List storage userDebtShare = lyfDs.subAccountDebtShares[_subAccount];

    if (
      lyfDs.subAccountDebtShares[_subAccount].getNextOf(LibUIntDoublyLinkedList.START) == LibUIntDoublyLinkedList.EMPTY
    ) {
      lyfDs.subAccountDebtShares[_subAccount].init();
    }

    uint256 _totalSupply = lyfDs.debtShares[_debtShareId];
    uint256 _totalValue = lyfDs.debtValues[_debtShareId];

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(_amount, _totalSupply, _totalValue);

    // update over collat debt
    lyfDs.debtShares[_debtShareId] += _shareToAdd;
    lyfDs.debtValues[_debtShareId] += _amount;

    uint256 _newShareAmount = userDebtShare.getAmount(_debtShareId) + _shareToAdd;

    // update user's debtshare
    userDebtShare.addOrUpdate(_debtShareId, _newShareAmount);
  }

  function repay(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken,
    uint256 _repayAmount
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];

    LibLYF01.accureInterest(_debtShareId, lyfDs);

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    (uint256 _oldSubAccountDebtShare, ) = _getDebt(_subAccount, _debtShareId, lyfDs);

    uint256 _shareToRemove = LibShareUtil.valueToShare(
      _repayAmount,
      lyfDs.debtShares[_debtShareId],
      lyfDs.debtValues[_debtShareId]
    );

    _shareToRemove = _oldSubAccountDebtShare > _shareToRemove ? _shareToRemove : _oldSubAccountDebtShare;

    uint256 _actualRepayAmount = _removeDebt(_subAccount, _debtShareId, _oldSubAccountDebtShare, _shareToRemove, lyfDs);

    // transfer only amount to repay
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _actualRepayAmount);

    emit LogRepay(_account, _subAccountId, _token, _actualRepayAmount);
  }

  function getDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    LibUIntDoublyLinkedList.List storage subAccountDebtShares = lyfDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  function getDebt(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken
  ) public view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];

    (_debtShare, _debtAmount) = _getDebt(_subAccount, _debtShareId, lyfDs);
  }

  function _getDebt(
    address _subAccount,
    uint256 _debtShareId,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _debtShare, uint256 _debtAmount) {
    _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);
    // Note: precision loss 1 wei when convert share back to value
    _debtAmount = LibShareUtil.shareToValue(_debtShare, lyfDs.debtValues[_debtShareId], lyfDs.debtShares[_debtShareId]);
  }

  function getGlobalDebt(address _token, address _lpToken) external view returns (uint256, uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return (lyfDs.debtShares[_debtShareId], lyfDs.debtValues[_debtShareId]);
  }

  function _removeDebt(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _oldSubAccountDebtShare,
    uint256 _shareToRemove,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal returns (uint256 _repayAmount) {
    uint256 _oldDebtShare = lyfDs.debtShares[_debtShareId];
    uint256 _oldDebtValue = lyfDs.debtValues[_debtShareId];

    // update user debtShare
    lyfDs.subAccountDebtShares[_subAccount].updateOrRemove(_debtShareId, _oldSubAccountDebtShare - _shareToRemove);

    // update over collat debtShare
    _repayAmount = LibShareUtil.shareToValue(_shareToRemove, _oldDebtValue, _oldDebtShare);

    lyfDs.debtShares[_debtShareId] -= _shareToRemove;
    lyfDs.debtValues[_debtShareId] -= _repayAmount;

    // emit event
    emit LogRemoveDebt(_subAccount, _debtShareId, _shareToRemove, _repayAmount);
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

    // todo: support debt share index
    _checkAvailableToken(_token, _amount, 0, lyfDs);
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
    uint256 _debtShareId,
    uint256 _borrowAmount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view {
    uint256 _mmTokenBalnce = ERC20(_token).balanceOf(address(this)) - lyfDs.collats[_token];

    if (_mmTokenBalnce < _borrowAmount) {
      revert LYFFarmFacet_NotEnoughToken(_borrowAmount);
    }

    if (_borrowAmount + lyfDs.debtValues[_debtShareId] > lyfDs.tokenConfigs[_token].maxBorrow) {
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

  function debtLastAccureTime(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtLastAccureTime[_debtShareId];
  }

  function pendingInterest(address _token, address _lpToken) public view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return LibLYF01.pendingInterest(_debtShareId, lyfDs);
  }

  function accureInterest(address _token, address _lpToken) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    LibLYF01.accureInterest(_debtShareId, lyfDs);
  }

  function debtValues(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtValues[_debtShareId];
  }

  function debtShares(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtShares[_debtShareId];
  }
}
