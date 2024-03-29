// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMiniFL {
  function poolLength() external view returns (uint256);

  function totalAllocPoint() external view returns (uint256);

  function alpacaPerSecond() external view returns (uint256);

  function getUserTotalAmountOf(uint256 _pid, address _user) external view returns (uint256 _totalAmount);

  function getPoolAllocPoint(uint256 _pid) external view returns (uint256 _allocPoint);

  function getStakingReserves(uint256 _pid) external view returns (uint256 _reserveAmount);

  function pendingAlpaca(uint256 _pid, address _user) external view returns (uint256);

  function getUserAmountFundedBy(
    address _funder,
    address _for,
    uint256 _pid
  ) external view returns (uint256 _stakingAmount);

  function addPool(
    uint256 _allocPoint,
    address _stakingToken,
    bool _withUpdate
  ) external returns (uint256 _pid);

  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amountToDeposit
  ) external;

  function withdraw(
    address _from,
    uint256 _pid,
    uint256 _amountToWithdraw
  ) external;

  function harvest(uint256 _pid) external;

  function harvestMany(uint256[] calldata _pids) external;

  function ALPACA() external view returns (address);
}
