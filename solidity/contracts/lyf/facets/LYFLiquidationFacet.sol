// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { ILYFLiquidationFacet } from "../interfaces/ILYFLiquidationFacet.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";

contract LYFLiquidationFacet is ILYFLiquidationFacet {
  using SafeERC20 for ERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;

  uint256 constant REPURCHASE_REWARD_BPS = 100;

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function repurchase(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    address _lpToken,
    uint256 _amountDebtToRepurchase
  ) external nonReentrant returns (uint256 _collatAmountOut) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtShareId = lyfDs.debtShareIds[_debtToken][_lpToken];

    LibLYF01.accureAllSubAccountDebtShares(_subAccount, lyfDs);

    // 1. check borrowing power
    uint256 _borrowingPower = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
    uint256 _borrowedValue = LibLYF01.getTotalBorrowedUSDValue(_subAccount, lyfDs);
    if (_borrowingPower > _borrowedValue) {
      revert LYFLiquidationFacet_Healthy();
    }

    // 2. calculate actual debt to repurchase, collat repurchaser will receive
    uint256 _actualDebtToRepurchase = _getActualDebtToRepurchase(
      _subAccount,
      _debtShareId,
      _amountDebtToRepurchase,
      lyfDs
    );

    // avoid stack too deep
    {
      (uint256 _debtTokenPrice, ) = LibLYF01.getPriceUSD(_debtToken, lyfDs);
      LibLYF01.TokenConfig memory _debtTokenConfig = lyfDs.tokenConfigs[_debtToken];
      uint256 _debtInUSD = (_actualDebtToRepurchase * _debtTokenConfig.to18ConversionFactor * _debtTokenPrice) / 1e18;
      if (_debtInUSD * 2 > _borrowedValue) {
        revert LYFLiquidationFacet_RepayDebtValueTooHigh();
      }

      _collatAmountOut = _calcCollatAmountRepurchaserReceive(
        _subAccount,
        _collatToken,
        _debtInUSD,
        REPURCHASE_REWARD_BPS,
        lyfDs
      );
    }

    // 3. reduce debt
    _reduceDebt(_subAccount, _debtShareId, _actualDebtToRepurchase, lyfDs);
    _reduceCollateral(_subAccount, _collatToken, _collatAmountOut, lyfDs);

    // 4. transfer
    ERC20(_debtToken).safeTransferFrom(msg.sender, address(this), _actualDebtToRepurchase);
    ERC20(_collatToken).safeTransfer(msg.sender, _collatAmountOut);

    emit LogRepurchase(msg.sender, _debtToken, _collatToken, _actualDebtToRepurchase, _collatAmountOut);
  }

  /// @dev min(amountToRepurchase, debtValue)
  function _getActualDebtToRepurchase(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _amountToRepurchase,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _actualToRepurchase) {
    uint256 _debtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);
    // Note: precision loss 1 wei when convert share back to value
    uint256 _debtValue = LibShareUtil.shareToValue(
      _debtShare,
      lyfDs.debtValues[_debtShareId],
      lyfDs.debtShares[_debtShareId]
    );

    _actualToRepurchase = _amountToRepurchase > _debtValue ? _debtValue : _amountToRepurchase;
  }

  function _calcCollatAmountRepurchaserReceive(
    address _subAccount,
    address _collatToken,
    uint256 _collatValueInUSD,
    uint256 _rewardBps,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal view returns (uint256 _collatAmountOut) {
    address _actualToken = IMoneyMarket(lyfDs.moneyMarket).ibTokenToTokens(_collatToken);

    uint256 _collatTokenPrice;
    // _collatToken is ibToken
    if (_actualToken != address(0)) {
      (_collatTokenPrice, ) = LibLYF01.getIbPriceUSD(_collatToken, _actualToken, lyfDs);
    } else {
      // _collatToken is normal ERC20 or LP token
      (_collatTokenPrice, ) = LibLYF01.getPriceUSD(_collatToken, lyfDs);
    }

    LibLYF01.TokenConfig memory _tokenConfig = lyfDs.tokenConfigs[_collatToken];

    // _collatAmountOut = _collatValueInUSD + _rewardInUSD
    _collatAmountOut =
      (_collatValueInUSD * (10000 + _rewardBps) * 1e14) /
      (_collatTokenPrice * _tokenConfig.to18ConversionFactor);

    uint256 _totalSubAccountCollat = lyfDs.subAccountCollats[_subAccount].getAmount(_collatToken);

    if (_collatAmountOut > _totalSubAccountCollat) {
      revert LYFLiquidationFacet_InsufficientAmount();
    }
  }

  function _reduceDebt(
    address _subAccount,
    uint256 _debtShareId,
    uint256 _amountToReduce,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    // calculate number of shares to reduce
    uint256 _shareToReduce = LibShareUtil.valueToShare(
      _amountToReduce,
      lyfDs.debtShares[_debtShareId],
      lyfDs.debtValues[_debtShareId]
    );

    // update subAccount debtShares
    uint256 _currentDebtShare = lyfDs.subAccountDebtShares[_subAccount].getAmount(_debtShareId);
    lyfDs.subAccountDebtShares[_subAccount].updateOrRemove(_debtShareId, _currentDebtShare - _shareToReduce);

    // update global debt
    lyfDs.debtShares[_debtShareId] -= _shareToReduce;
    lyfDs.debtValues[_debtShareId] -= _amountToReduce;
  }

  function _reduceCollateral(
    address _subAccount,
    address _collatToken,
    uint256 _amountToReduce,
    LibLYF01.LYFDiamondStorage storage lyfDs
  ) internal {
    uint256 _collatTokenAmount = lyfDs.subAccountCollats[_subAccount].getAmount(_collatToken);
    lyfDs.subAccountCollats[_subAccount].updateOrRemove(_collatToken, _collatTokenAmount - _amountToReduce);
    lyfDs.collats[_collatToken] -= _amountToReduce;
  }
}
