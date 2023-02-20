// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// ---- Interfaces ---- //
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";

/// @title LendFacet is dedicated for depositing and withdrawing token for lending
contract LendFacet is ILendFacet {
  using LibSafeToken for IERC20;

  event LogDeposit(
    address indexed _for,
    address indexed _token,
    address _caller,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );
  event LogWithdraw(
    address indexed _for,
    address indexed _token,
    address _caller,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @dev separate reentrancy lock to allow liquidation strategies
  ///      to do reentrant withdraw during liquidation process
  modifier nonReentrantWithdraw() {
    LibReentrancyGuard.lockWithdraw();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Deposit a token for lending
  /// @param _for The actual lender. Used only for tracking purpose
  /// @param _token The token to lend
  /// @param _amount The amount to lend
  /// @return _shareAmount The share amount gained from deposit
  function deposit(
    address _for,
    address _token,
    uint256 _amount
  ) external nonReentrant returns (uint256 _shareAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This will revert if markets are paused
    LibMoneyMarket01.onlyLive(moneyMarketDs);

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];
    // Revert if market doesn't exist for _token
    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_token);
    }

    // Accrue interest so that ib amount calculation would be correct
    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    // Calculate ib amount from underlyingAmount
    (, _shareAmount) = LibMoneyMarket01.getShareAmountFromValue(_token, _ibToken, _amount, moneyMarketDs);

    // Increase underlying token balance
    // Safe to use unchecked because amount can't overflow (amount <= totalSupply)
    unchecked {
      moneyMarketDs.reserves[_token] += _amount;
    }

    // Transfer token in, Revert if fee on transfer
    LibMoneyMarket01.pullExactTokens(_token, msg.sender, _amount);
    // Callback to ibToken to mint ibToken to msg.sender and emit ERC-4626 Deposit event
    IInterestBearingToken(_ibToken).onDeposit(msg.sender, _amount, _shareAmount);

    // _for is purely used for event tracking purpose
    // since this function will be called from only AccountManager
    // we need a way to track the actual lender
    emit LogDeposit(_for, _token, msg.sender, _ibToken, _amount, _shareAmount);
  }

  /// @notice Withdraw the lended token by burning the interest bearing token
  /// @param _for The actual owner. Used only for tracking purpose
  /// @param _ibToken The interest bearing token to burn
  /// @param _shareAmount The amount of interest bearing token to burn
  /// @return _withdrawAmount The amount withdrawn
  function withdraw(
    address _for,
    address _ibToken,
    uint256 _shareAmount
  ) external nonReentrantWithdraw returns (uint256 _withdrawAmount) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // This function should not be called from anyone
    // except account manager contract and will revert upon trying to do so
    LibMoneyMarket01.onlyAccountManager(moneyMarketDs);

    address _underlyingToken = moneyMarketDs.ibTokenToTokens[_ibToken];
    // Revert if market doesn't exist for _ibToken
    if (_underlyingToken == address(0)) {
      revert LendFacet_InvalidToken(_ibToken);
    }

    // Accrue interest so that ib amount calculation would be correct
    LibMoneyMarket01.accrueInterest(_underlyingToken, moneyMarketDs);

    // TODO: move withdraw from lib to here and comment
    _withdrawAmount = LibMoneyMarket01.withdraw(_underlyingToken, _ibToken, _shareAmount, moneyMarketDs);

    // Reduce _underlyingToken balance
    // Safe to use unchecked here because we already check that `_withdrawAmount < reserves`
    unchecked {
      moneyMarketDs.reserves[_underlyingToken] -= _withdrawAmount;
    }

    IERC20(_underlyingToken).safeTransfer(msg.sender, _withdrawAmount);

    // _for is purely used for event tracking purpose
    // since this function will be called from only AccountManager
    // we need a way to track the actual lender
    emit LogWithdraw(_for, _underlyingToken, msg.sender, _ibToken, _shareAmount, _withdrawAmount);
  }
}
