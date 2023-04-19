// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "../interfaces/IERC20.sol";
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";

contract MockMoneyMarketV3 {
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

  function withdraw(
    address, /* _for */
    address _ibToken,
    uint256 /*_shareAmount*/
  ) external returns (uint256 _shareValue) {
    _shareValue = _withdrawalAmount;
    // must burn here
    // InterestBearingToken(_ibToken).onWithdraw(msg.sender, msg.sender, 0, _shareValue);
    IERC20(_ibToTokens[_ibToken]).transfer(msg.sender, _shareValue);
  }
}
