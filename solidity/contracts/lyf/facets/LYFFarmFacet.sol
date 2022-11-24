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
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";

contract LYFFarmFacet is ILYFFarmFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  error LYFFarmFacet_BorrowingPowerTooLow();
  error LYFFarmFacet_InvalidLPConfig(address _lpToken);

  event LogRemoveDebt(
    address indexed _subAccount,
    address indexed _token,
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
    uint256 _minLpReceive
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    LibLYF01.LPConfig memory lpConfig = lyfDs.lpConfigs[_lpToken];

    if (lpConfig.strategy == address(0) || lpConfig.masterChef == address(0)) {
      revert LYFFarmFacet_InvalidLPConfig(_lpToken);
    }

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

    // 1. check subaccount collat
    uint256 _token0AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token0, _desireToken0Amount, lyfDs);
    uint256 _token1AmountFromCollat = LibLYF01.removeCollateral(_subAccount, _token1, _desireToken1Amount, lyfDs);

    //2. borrow from mm if collats do not cover the desire amount
    _borrowFromMoneyMarket(_subAccount, _token0, _desireToken0Amount - _token0AmountFromCollat, lyfDs);
    _borrowFromMoneyMarket(_subAccount, _token1, _desireToken1Amount - _token1AmountFromCollat, lyfDs);

    // 3. send token to strat
    ERC20(_token0).safeTransfer(lpConfig.strategy, _desireToken0Amount);
    ERC20(_token1).safeTransfer(lpConfig.strategy, _desireToken1Amount);

    // 4. compose lp
    uint256 _lpReceived = IStrat(lpConfig.strategy).composeLPToken(
      _token0,
      _token1,
      _lpToken,
      _desireToken0Amount,
      _desireToken1Amount,
      _minLpReceive
    );

    // 5. deposit to masterChef
    IStrat(lpConfig.strategy).depositMasterChef(lpConfig.poolId, lpConfig.masterChef, _lpReceived);

    // 6. add it to collateral
    LibLYF01.addCollat(_subAccount, _lpToken, _lpReceived, lyfDs);

    // 7. health check on sub account
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFFarmFacet_BorrowingPowerTooLow();
    }
    emit LogAddFarmPosition(_subAccount, _lpToken, _lpReceived);
  }

  function liquidateLP(
    uint256 _subAccountId,
    address _lpToken,
    uint256 _lpShareAmount
  ) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    if (lyfDs.tokenConfigs[_lpToken].tier != LibLYF01.AssetTier.LP) {
      revert LYFFarmFacet_InvalidAssetTier();
    }

    address _removeStrat = lyfDs.lpConfigs[_lpToken].strategy;
    if (_removeStrat == address(0)) {
      revert LYFFarmFacet_InvalidLPConfig(_lpToken);
    }

    address _token0 = ISwapPairLike(_lpToken).token0();
    address _token1 = ISwapPairLike(_lpToken).token1();

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
    uint256 _amount,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    if (_amount == 0) return;

    IMoneyMarket(lyfDs.moneyMarket).nonCollatBorrow(_token, _amount);

    // update subaccount debt
    // todo: optimize this
    LibDoublyLinkedList.List storage userDebtShare = lyfDs.subAccountDebtShares[_subAccount];

    if (lyfDs.subAccountDebtShares[_subAccount].getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      lyfDs.subAccountDebtShares[_subAccount].init();
    }

    uint256 _totalSupply = lyfDs.debtShares[_token];
    uint256 _totalValue = lyfDs.debtValues[_token];

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(_totalSupply, _amount, _totalValue);

    // update over collat debt
    lyfDs.debtShares[_token] += _shareToAdd;
    lyfDs.debtValues[_token] += _amount;

    uint256 _newShareAmount = userDebtShare.getAmount(_token) + _shareToAdd;

    // update user's debtshare
    userDebtShare.addOrUpdate(_token, _newShareAmount);
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

  function getMMDebt(address _token) external view returns (uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _debtAmount = IMoneyMarket(lyfDs.moneyMarket).nonCollatGetDebt(address(this), _token);
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
