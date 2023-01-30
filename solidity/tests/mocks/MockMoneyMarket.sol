// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IMoneyMarket } from "../../contracts/money-market/interfaces/IMoneyMarket.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract MockMoneyMarket is IMoneyMarket {
  mapping(address => address) private _ibToTokens;
  uint256 private _withdrawalAmount;

  function setIbToken(address _ibToken, address _token) external {
    _ibToTokens[_ibToken] = _token;
  }

  function setWithdrawalAmount(uint256 withdrawalAmount_) external {
    _withdrawalAmount = withdrawalAmount_;
  }

  function getTotalToken(address _token) public view returns (uint256) {
    return IERC20(_token).balanceOf(address(this));
  }

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken) {
    // todo support interest
    _totalToken = getTotalToken(_token);
  }

  function getTokenFromIbToken(address _ibToken) external view returns (address) {
    return _ibToTokens[_ibToken];
  }

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue) {
    _shareValue = _withdrawalAmount;
    IERC20(_ibToken).transferFrom(msg.sender, address(this), _shareAmount);
    IERC20(_ibToTokens[_ibToken]).transfer(msg.sender, _shareValue);
  }
}
