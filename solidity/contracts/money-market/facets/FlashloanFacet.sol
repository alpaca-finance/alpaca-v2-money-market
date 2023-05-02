// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { LibConstant } from "../libraries/LibConstant.sol";

// interfaces
import { IFlashloanFacet } from "../interfaces/IFlashloanFacet.sol";
import { IAlpacaFlashloan } from "../interfaces/IAlpacaFlashloan.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract FlashloanFacet is IFlashloanFacet {
  using LibSafeToken for IERC20;

  // error
  error FlashloanFacet_InvalidToken(address _token);
  error FlashloanFacet_NotEnoughToken(uint256 _amount);
  error FlashloanFacet_NotEnoughRepay();

  // external call for using flashloan
  function flashloan(address _token, uint256 _amount) external {
    // prep
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // check if fee is set?

    // 1. is market open for this token? (ib token from token)
    // Revert if market doesn't exist for `_token`
    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) {
      revert FlashloanFacet_InvalidToken(_token);
    }

    // 2. token reserve > borrow amount
    if (moneyMarketDs.reserves[_token] < _amount) {
      revert FlashloanFacet_NotEnoughToken(_amount);
    }

    // 3. expected fee = (_amount * feeBps) / maxBps
    uint256 _expectedFee = (_amount * moneyMarketDs.flashLoanFeeBps) / LibConstant.MAX_BPS;

    // balance before
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransfer(msg.sender, _amount);

    // 4. call AlpacaFlashloanCallback (AlpacaFlashloanCallback must return repay)
    IAlpacaFlashloan(msg.sender).AlpacaFlashloanCallback(_token, _amount);

    // balance after
    uint256 _balanceAfter = IERC20(_token).balanceOf(address(this));

    // 5. repay must be excess balance before + fee (revert if condition is not met)
    if (_balanceAfter <= _balanceBefore + _expectedFee) {
      revert FlashloanFacet_NotEnoughRepay();
    }

    uint256 _actualTotalFee = _balanceAfter - _balanceBefore;

    // 6. 50% of fee add to reserve
    uint256 _lenderFee = (_expectedFee * 50) / 100;

    // lender fee (add on reserve)
    moneyMarketDs.reserves[_token] += _lenderFee;

    // transfer the rest of fee to protocol reserve
    moneyMarketDs.protocolReserves[_token] += (_actualTotalFee - _lenderFee);
  }
}
