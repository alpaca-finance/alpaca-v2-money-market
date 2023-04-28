// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// libraries
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// interfaces
import { IAlpacaFlashloan } from "../interfaces/IAlpacaFlashloan.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract FlashloanFacet {
  using LibSafeToken for IERC20;

  // error
  error FlashloanFacet_InvalidToken(address _token);
  error FlashloanFacet_NotEnoughToken(uint256 _amount);
  error FlashloanFacet_NotEnoughRepay();

  // external call for using flashloan
  function flashloan(address _token, uint256 _amount) external {
    // prep
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // 1. is market open for this token? (ib token from token)
    // Revert if market doesn't exist for `_token`
    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) {
      revert FlashloanFacet_InvalidToken(_token);
    }

    // 2. token reserve > _amount
    if (moneyMarketDs.reserves[_token] < _amount) {
      revert FlashloanFacet_NotEnoughToken(_amount);
    }

    // TODO: How much fee?
    // 3. expected repay = _amount + total fee
    uint256 _totalFee = (_amount * 101) / 100;

    // TODO
    // 3.5 lender fee = 50 % total fee
    uint256 _lenderFee = _totalFee / 2;
    // uint256 _repayAmount = _amount + _totalFee;

    // 4. transfer token from xx to msg.sender
    // TODO: update state?
    // Update the global reserve of the token, as a result less borrowing can be made

    IERC20(_token).safeTransfer(msg.sender, _amount);

    // balance before
    uint256 _balanceBefore = IERC20(_token).balanceOf(address(this));

    // 5. call AlpacaFlashloanCallback (AlpacaFlashloanCallback must return repay)
    IAlpacaFlashloan(msg.sender).AlpacaFlashloanCallback();
    // TODO: update state?
    uint256 _balanceAfter = IERC20(_token).balanceOf(address(this));

    // borrow 100
    // fee 5%
    // repay = 105
    // 105 >= 100 + 5

    // 6. repay must be exceed the expected repay (revert if condition is not met)
    if (_balanceAfter >= _balanceBefore + _totalFee) {
      revert FlashloanFacet_NotEnoughRepay();
    }

    // 7. the excess repay will be added to reserve
    // TODO: transfer fee to lender
    // IERC20(_token).safeTransfer(msg.sender, _amount);

    // TODO: transfer exceed fee to protocol reserve
    // IERC20(_token).safeTransfer(msg.sender, _amount);
  }
}
