// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IMoneyMarket {
  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function nonCollatBorrow(address _token, uint256 _amount) external;

  function nonCollatRepay(
    address _account,
    address _token,
    uint256 _repayAmount
  ) external;

  function getGlobalDebtValue(address _token) external view returns (uint256);

  function getGlobalDebtValueWithPendingInterest(address _token) external view returns (uint256);

  function getDebtForLpToken(address _token) external view returns (uint256, uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function nonCollatGetDebt(address _account, address _token) external view returns (uint256 _debtAmount);

  function withdraw(
    address _for,
    address _ibToken,
    uint256 _shareAmount
  ) external returns (uint256 _shareValue);

  function deposit(
    address _for,
    address _token,
    uint256 _amount
  ) external returns (uint256 _shareAmount);

  function setAccountManagersOk(address[] calldata _list, bool _isOk) external;
}
