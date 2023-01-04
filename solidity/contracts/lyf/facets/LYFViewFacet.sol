// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { ILYFViewFacet } from "../interfaces/ILYFViewFacet.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
// libraries
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibUIntDoublyLinkedList } from "../libraries/LibUIntDoublyLinkedList.sol";

contract LYFViewFacet is ILYFViewFacet {
  using LibUIntDoublyLinkedList for LibUIntDoublyLinkedList.List;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  function getOracle() external view returns (address) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.oracle;
  }

  function getLpTokenConfig(address _lpToken) external view returns (LibLYF01.LPConfig memory) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpConfigs[_lpToken];
  }

  function getLpTokenAmount(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpAmounts[_lpToken];
  }

  function getLpTokenShare(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.lpShares[_lpToken];
  }

  function getAllSubAccountCollats(address _account, uint256 _subAccountId)
    external
    view
    returns (LibDoublyLinkedList.Node[] memory)
  {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    LibDoublyLinkedList.List storage subAccountCollateralList = ds.subAccountCollats[_subAccount];
    return subAccountCollateralList.getAll();
  }

  function getTokenCollatAmount(address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    return ds.collats[_token];
  }

  function getSubAccountTokenCollatAmount(address _subAccount, address _token) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage ds = LibLYF01.lyfDiamondStorage();
    return ds.subAccountCollats[_subAccount].getAmount(_token);
  }

  function getMMDebt(address _token) external view returns (uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _debtAmount = IMoneyMarket(lyfDs.moneyMarket).getNonCollatAccountDebt(address(this), _token);
  }

  function getDebtForLpToken(address _token, address _lpToken) external view returns (uint256, uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return (lyfDs.debtShares[_debtShareId], lyfDs.debtValues[_debtShareId]);
  }

  function getTokenDebtValue(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtValues[_debtShareId];
  }

  function getTokenDebtShare(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtShares[_debtShareId];
  }

  function getSubAccountDebt(
    address _account,
    uint256 _subAccountId,
    address _token,
    address _lpToken
  ) public view returns (uint256 _debtShare, uint256 _debtAmount) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];

    (_debtShare, _debtAmount) = LibLYF01.getDebt(_subAccount, _debtShareId, lyfDs);
  }

  function getAllSubAccountDebtShares(address _account, uint256 _subAccountId)
    external
    view
    returns (LibUIntDoublyLinkedList.Node[] memory)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    LibUIntDoublyLinkedList.List storage subAccountDebtShares = lyfDs.subAccountDebtShares[_subAccount];

    return subAccountDebtShares.getAll();
  }

  function getDebtLastAccrueTime(address _token, address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return lyfDs.debtLastAccrueTime[_debtShareId];
  }

  function getPendingInterest(address _token, address _lpToken) public view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _debtShareId = lyfDs.debtShareIds[_token][_lpToken];
    return LibLYF01.pendingInterest(_debtShareId, lyfDs);
  }

  function getPendingReward(address _lpToken) external view returns (uint256) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return lyfDs.pendingRewards[_lpToken];
  }

  function getTotalBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowingPowerUSDValue)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    _totalBorrowingPowerUSDValue = LibLYF01.getTotalBorrowingPower(_subAccount, lyfDs);
  }

  function getTotalUsedBorrowingPower(address _account, uint256 _subAccountId)
    external
    view
    returns (uint256 _totalBorrowedUSDValue)
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    _totalBorrowedUSDValue = LibLYF01.getTotalUsedBorrowingPower(_subAccount, lyfDs);
  }

  function getMaxNumOfToken() external view returns (uint8 _maxNumOfCollat) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    _maxNumOfCollat = lyfDs.maxNumOfCollatPerSubAccount;
  }
}
