// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract LendFacet is ILendFacet {
  using SafeERC20 for ERC20;

  event LogDeposit(
    address indexed _user,
    address _token,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  event LogWithdraw(
    address indexed _user,
    address _token,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  function deposit(address _token, uint256 _amount) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _accureInterest(_token, moneyMarketDs);
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_token);
    }
    uint256 _totalSupply = IIbToken(_ibToken).totalSupply();

    uint256 _totalToken = _getTotalToken(_token, moneyMarketDs);

    // calculate _shareToMint to mint before transfer token to MM
    uint256 _shareToMint = LibShareUtil.valueToShare(
      _totalSupply,
      _amount,
      _totalToken
    );

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IIbToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _shareToMint);
  }

  function withdraw(address _ibToken, uint256 _shareAmount) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _token = moneyMarketDs.ibTokenToTokens[_ibToken];

    if (_token == address(0)) {
      revert LendFacet_InvalidToken(_ibToken);
    }
    _accureInterest(_token, moneyMarketDs);

    uint256 _totalSupply = IIbToken(_ibToken).totalSupply();
    uint256 _totalToken = _getTotalToken(_token, moneyMarketDs);

    uint256 _shareValue = LibShareUtil.shareToValue(
      _totalToken,
      _shareAmount,
      _totalSupply
    );

    IIbToken(_ibToken).burn(msg.sender, _shareAmount);
    ERC20(_token).transfer(msg.sender, _shareValue);

    emit LogWithdraw(msg.sender, _token, _ibToken, _shareAmount, _shareValue);
  }

  // totalToken is the amount of token remains in MM + borrowed amount - collateral from user
  // where borrowed amount consists of over-collat and non-collat borrowing
  function _getTotalToken(
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256) {
    // TODO: optimize this by using global state var
    uint256 _nonCollatDebt = LibMoneyMarket01.getNonCollatTokenDebt(
      _token,
      moneyMarketDs
    );
    return
      (ERC20(_token).balanceOf(address(this)) +
        moneyMarketDs.debtValues[_token] +
        _nonCollatDebt) - moneyMarketDs.collats[_token];
  }

  function getTotalToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return _getTotalToken(_token, moneyMarketDs);
  }

  function accureInterest(address _token) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    _accureInterest(_token, moneyMarketDs);
  }

  function getDebtLastAccureTime(address _token)
    external
    view
    returns (uint256)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.debtLastAccureTime[_token];
  }

  function _accureInterest(
    address _token,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    if (block.timestamp > moneyMarketDs.debtLastAccureTime[_token]) {
      uint256 interest = pendingInterest(_token);
      // uint256 toReserve = interest.mul(moneyMarketDs.getReservePoolBps()).div(
      //   10000
      // );
      // reservePool = reservePool.add(toReserve);

      moneyMarketDs.debtValues[_token] += interest;
      moneyMarketDs.debtLastAccureTime[_token] = block.timestamp;
    }
  }

  /// @dev Return the pending interest that will be accrued in the next call.
  /// @param _token Token for get lastAccurTime
  function pendingInterest(address _token) public view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _lastAccureTime = moneyMarketDs.debtLastAccureTime[_token];

    if (block.timestamp > _lastAccureTime) {
      uint256 timePast = block.timestamp - _lastAccureTime;
      // uint256 balance = ERC20(_token).balanceOf(address(this));
      if (address(moneyMarketDs.interestModels[_token]) == address(0)) {
        return 0;
      }

      uint256 _interestRate = IInterestRateModel(
        moneyMarketDs.interestModels[_token]
      ).getInterestRate(moneyMarketDs.debtValues[_token], 0);
      //FIXME change it when dynamically comes
      return _interestRate * timePast;
      // return ratePerSec.mul(vaultDebtVal).mul(timePast).div(1e18);
    } else {
      return 0;
    }
  }
}
