// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMoneyMarket {
  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function getGlobalDebtValue(address _token) external view returns (uint256);

  function getOverCollatTokenDebt(address _token) external view returns (uint256, uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function getNonCollatAccountDebt(address _account, address _token) external view returns (uint256 _debtAmount);

  function withdraw(address _ibToken, uint256 _shareAmount) external returns (uint256 _shareValue);

  function deposit(address _token, uint256 _amount) external;

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken);

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external;

  function accrueInterest(address _token) external;
}
