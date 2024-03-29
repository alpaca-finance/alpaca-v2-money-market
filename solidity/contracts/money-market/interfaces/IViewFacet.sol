// SPDX-License-Identifier: BUSL
pragma solidity >=0.8.19;

// libs
import { LibConstant } from "../libraries/LibConstant.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

interface IViewFacet {
  function getIbTokenFromToken(address _token) external view returns (address);

  function getTokenFromIbToken(address _ibToken) external view returns (address);

  function getMiniFLPoolIdOfToken(address _token) external view returns (uint256);

  function getProtocolReserve(address _token) external view returns (uint256 _reserve);

  function getTokenConfig(address _token) external view returns (LibConstant.TokenConfig memory);

  function getOverCollatDebtSharesOf(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPower);

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalUsedBorrowingPower, bool _hasIsolateAsset);

  function getTotalNonCollatUsedBorrowingPower(address _account)
    external
    view
    returns (uint256 _totalUsedBorrowingPower);

  function getOverCollatTokenDebt(address _token) external view returns (uint256 _debtShares, uint256 _debtValue);

  function getDebtLastAccruedAt(address _token) external view returns (uint256);

  function getOverCollatInterestRate(address _token) external view returns (uint256);

  function getOverCollatInterestModel(address _token) external view returns (address);

  function getOverCollatPendingInterest(address _token) external view returns (uint256 _pendingInterest);

  function getNonCollatPendingInterest(address _account, address _token)
    external
    view
    returns (uint256 _pendingInterest);

  function getGlobalPendingInterest(address _token) external view returns (uint256);

  function getGlobalDebtValue(address _token) external view returns (uint256);

  function getGlobalDebtValueWithPendingInterest(address _token) external view returns (uint256);

  function getOverCollatTokenDebtValue(address _token) external view returns (uint256);

  function getOverCollatTokenDebtShares(address _token) external view returns (uint256);

  function getFloatingBalance(address _token) external view returns (uint256);

  function getOverCollatDebtShareAndAmountOf(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256 _debtShare, uint256 _debtAmount);

  function getAllSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory);

  function getTotalCollat(address _token) external view returns (uint256);

  function getCollatAmountOf(
    address _account,
    uint256 _subAccountId,
    address _token
  ) external view returns (uint256);

  function getTotalToken(address _token) external view returns (uint256);

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256);

  function getNonCollatAccountDebtValues(address _account) external view returns (LibDoublyLinkedList.Node[] memory);

  function getNonCollatAccountDebt(address _account, address _token) external view returns (uint256);

  function getNonCollatTokenDebt(address _token) external view returns (uint256);

  function getNonCollatBorrowingPower(address _account) external view returns (uint256);

  function getNonCollatInterestRate(address _account, address _token) external view returns (uint256);

  function getLiquidationParams() external view returns (uint16 maxLiquidateBps, uint16 liquidationThresholdBps);

  function getMaxNumOfToken()
    external
    view
    returns (
      uint8,
      uint8,
      uint8
    );

  function getSubAccount(address _account, uint256 _subAccountId) external pure returns (address);

  function getMinDebtSize() external view returns (uint256);

  function getFeeParams()
    external
    view
    returns (
      uint16 _lendingFeeBps,
      uint16 _repurchaseFeeBps,
      uint16 _liquidationFeeBps
    );

  function getFlashloanParams()
    external
    view
    returns (
      uint16 _flashloanFeeBps,
      uint16 _lenderFlashloanBps,
      address _flashloanTreasury
    );

  function getRepurchaseRewardModel() external view returns (address);

  function getIbTokenImplementation() external view returns (address);

  function getDebtTokenFromToken(address _token) external view returns (address);

  function getDebtTokenImplementation() external view returns (address);

  function getLiquidationTreasury() external view returns (address _liquidationTreasury);

  function getOracle() external view returns (address);

  function getMiniFL() external view returns (address);

  function isLiquidationStratOk(address _strat) external view returns (bool);

  function isLiquidatorOk(address _liquidator) external view returns (bool);

  function isAccountManagersOk(address _accountManger) external view returns (bool);

  function isRiskManagersOk(address _riskManager) external view returns (bool);

  function isOperatorsOk(address _operator) external view returns (bool);
}
