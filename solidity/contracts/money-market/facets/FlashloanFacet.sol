// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { LibConstant } from "../libraries/LibConstant.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { IFlashloanFacet } from "../interfaces/IFlashloanFacet.sol";
import { IAlpacaFlashloanCallback } from "../interfaces/IAlpacaFlashloanCallback.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract FlashloanFacet is IFlashloanFacet {
  using LibSafeToken for IERC20;

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  // Event
  event LogFlashloan(
    address _token,
    uint256 _amount,
    uint256 _feeToLenders,
    uint256 _feeToProtocol,
    uint256 _excessFee
  );

  /// @notice Loan token and pay it back, plus fee, in the callback
  /// @dev The caller of this method receives a callback in the form of IAlpacaFlashloanCallback#alpacaFlashloanCallback
  /// @param _token The address of loan token
  /// @param _amount The amount of the loan token
  /// @param _data Any data to be passed through to the callback
  function flashloan(
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // only allow flashloan on opened market
    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) {
      revert FlashloanFacet_InvalidToken();
    }

    // expected fee = (_amount * flashloan fee (bps)) / max bps
    uint256 _expectedFee = (_amount * moneyMarketDs.flashloanFeeBps) / LibConstant.MAX_BPS;

    if (_expectedFee == 0) {
      revert FlashloanFacet_NoFee();
    }

    // cache balance before sending token to flashloaner
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransfer(msg.sender, _amount);

    // initiate callback at sender's contract
    IAlpacaFlashloanCallback(msg.sender).alpacaFlashloanCallback(_token, _amount + _expectedFee, _data);

    // revert if the returned amount did not cover fee
    uint256 _actualTotalFee = IERC20(_token).balanceOf(address(this)) - _balanceBefore;
    if (_actualTotalFee < _expectedFee) {
      revert FlashloanFacet_NotEnoughRepay();
    }

    // transfer excess fee to treasury
    // in case flashloaner inject a lot of fee, the ib token price should not be inflated
    // this is to prevent unforeseeable impact from inflating the ib token price
    uint256 _excessFee;
    if (_actualTotalFee > _expectedFee) {
      unchecked {
        _excessFee = _actualTotalFee - _expectedFee;
      }

      IERC20(_token).safeTransfer(moneyMarketDs.flashloanTreasury, _excessFee);
    }

    // calculate the actual lender fee by taking x% of expected fee
    uint256 _feeToLenders = (_expectedFee * moneyMarketDs.lenderFlashloanBps) / LibConstant.MAX_BPS;

    // expected fee will be added to reserve
    moneyMarketDs.reserves[_token] += _expectedFee;
    // the rest of the fee will go to protocol
    uint256 _feeToProtocol;
    unchecked {
      _feeToProtocol = _expectedFee - _feeToLenders;
    }
    moneyMarketDs.protocolReserves[_token] += _feeToProtocol;

    emit LogFlashloan(_token, _amount, _feeToLenders, _feeToProtocol, _excessFee);
  }
}
