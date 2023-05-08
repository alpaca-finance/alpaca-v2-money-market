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

    // expected fee = (_amount * flashloan fee (bps)) / max bps
    uint256 _expectedFee = (_amount * moneyMarketDs.flashloanFeeBps) / LibConstant.MAX_BPS;

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

    // calculate the actual lender fee by taking x% of expected fee
    // in case flashloaner inject a lot of fee, the ib token price should not be inflated
    // this is to prevent unforeseeable impact from inflating the ib token price
    uint256 _lenderFee = (_expectedFee * moneyMarketDs.lenderFlashloanBps) / LibConstant.MAX_BPS;

    // total actual fee will be added to reserve (including excess fee)
    moneyMarketDs.reserves[_token] += _actualTotalFee;
    // the rest of the fee will go to protocol
    moneyMarketDs.protocolReserves[_token] += _actualTotalFee - _lenderFee;

    emit LogFlashloan(_token, _amount, _actualTotalFee, _lenderFee);
  }
}
