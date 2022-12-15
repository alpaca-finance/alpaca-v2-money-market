// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibLendingReward } from "../libraries/LibLendingReward.sol";
import { LibBorrowingReward } from "../libraries/LibBorrowingReward.sol";

// interfaces
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";

contract AdminFacet is IAdminFacet {
  using SafeCast for uint256;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogSetRewardDistributor(address indexed _address);
  event LogAddRewardPerSec(address indexed _rewardToken, uint256 _rewardPerSec);
  event LogUpdateRewardPerSec(address indexed _rewardToken, uint256 _rewardPerSec);
  event LogAddLendingPool(address indexed _token, address indexed _rewardToken, uint256 _allocPoint);
  event LogSetLendingPool(address indexed _token, address indexed _rewardToken, uint256 _allocPoint);
  event LogAddBorroweringPool(address indexed _token, address indexed _rewardToken, uint256 _allocPoint);
  event LogSetBorrowingPool(address indexed _token, address indexed _rewardToken, uint256 _allocPoint);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function setTokenToIbTokens(IbPair[] memory _ibPair) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _ibPairLength = _ibPair.length;
    for (uint8 _i; _i < _ibPairLength; ) {
      LibMoneyMarket01.setIbPair(_ibPair[_i].token, _ibPair[_i].ibToken, moneyMarketDs);
      unchecked {
        _i++;
      }
    }
  }

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _inputLength = _tokenConfigs.length;
    for (uint8 _i; _i < _inputLength; ) {
      LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01.TokenConfig({
        tier: _tokenConfigs[_i].tier,
        collateralFactor: _tokenConfigs[_i].collateralFactor,
        borrowingFactor: _tokenConfigs[_i].borrowingFactor,
        maxCollateral: _tokenConfigs[_i].maxCollateral,
        maxBorrow: _tokenConfigs[_i].maxBorrow,
        maxToleranceExpiredSecond: _tokenConfigs[_i].maxToleranceExpiredSecond,
        to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_tokenConfigs[_i].token)
      });

      LibMoneyMarket01.setTokenConfig(_tokenConfigs[_i].token, _tokenConfig, moneyMarketDs);

      unchecked {
        _i++;
      }
    }
  }

  function setNonCollatBorrower(address _borrower, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.nonCollatBorrowerOk[_borrower] = _isOk;
  }

  function tokenToIbTokens(address _token) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.tokenToIbTokens[_token];
  }

  function ibTokenToTokens(address _ibToken) external view returns (address) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return moneyMarketDs.ibTokenToTokens[_ibToken];
  }

  function tokenConfigs(address _token) external view returns (LibMoneyMarket01.TokenConfig memory) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    return moneyMarketDs.tokenConfigs[_token];
  }

  function setInterestModel(address _token, address _model) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.interestModels[_token] = IInterestRateModel(_model);
  }

  function setNonCollatInterestModel(
    address _account,
    address _token,
    address _model
  ) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _nonCollatId = LibMoneyMarket01.getNonCollatId(_account, _token);
    moneyMarketDs.nonCollatInterestModels[_nonCollatId] = IInterestRateModel(_model);
  }

  function setOracle(address _oracle) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.oracle = IAlpacaV2Oracle(_oracle);
  }

  function setRepurchasersOk(address[] memory list, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = list.length;
    for (uint8 _i; _i < _length; ) {
      moneyMarketDs.repurchasersOk[list[_i]] = _isOk;
      unchecked {
        _i++;
      }
    }
  }

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = list.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.liquidationStratOk[list[_i]] = _isOk;
      unchecked {
        _i++;
      }
    }
  }

  function setLiquidationCallersOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = list.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.liquidationCallersOk[list[_i]] = _isOk;
      unchecked {
        _i++;
      }
    }
  }

  function setTreasury(address newTreasury) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.treasury = newTreasury;
  }

  function setNonCollatBorrowLimitUSDValues(NonCollatBorrowLimitInput[] memory _nonCollatBorrowLimitInputs)
    external
    onlyOwner
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _nonCollatBorrowLimitInputs.length;
    for (uint8 _i; _i < _length; ) {
      NonCollatBorrowLimitInput memory input = _nonCollatBorrowLimitInputs[_i];
      moneyMarketDs.nonCollatBorrowLimitUSDValues[input.account] = input.limit;
      unchecked {
        _i++;
      }
    }
  }

  function setRewardDistributor(address _addr) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.rewardDistributor = _addr;

    emit LogSetRewardDistributor(_addr);
  }

  function getLendingRewardPerSec(address _rewardToken) external view onlyOwner returns (uint256 _rewardPerSec) {
    _rewardPerSec = LibMoneyMarket01.moneyMarketDiamondStorage().lendingRewardPerSecList.getAmount(_rewardToken);
  }

  function getBorrowingRewardPerSec(address _rewardToken) external view onlyOwner returns (uint256 _rewardPerSec) {
    _rewardPerSec = LibMoneyMarket01.moneyMarketDiamondStorage().borrowingRewardPerSecList.getAmount(_rewardToken);
  }

  function addLendingRewardPerSec(address _rewardToken, uint256 _rewardPerSec) external onlyOwner {
    LibDoublyLinkedList.List storage rewardPerSecList = LibMoneyMarket01
      .moneyMarketDiamondStorage()
      .lendingRewardPerSecList;
    if (rewardPerSecList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      rewardPerSecList.init();
    }
    rewardPerSecList.add(_rewardToken, _rewardPerSec);

    emit LogAddRewardPerSec(_rewardToken, _rewardPerSec);
  }

  function updateLendingRewardPerSec(address _rewardToken, uint256 _rewardPerSec) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibDoublyLinkedList.List storage rewardPerSecList = moneyMarketDs.lendingRewardPerSecList;
    if (rewardPerSecList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      rewardPerSecList.init();
    }

    LibLendingReward.massUpdatePoolInReward(_rewardToken, moneyMarketDs);

    rewardPerSecList.updateOrRemove(_rewardToken, _rewardPerSec);

    emit LogUpdateRewardPerSec(_rewardToken, _rewardPerSec);
  }

  function addBorrowingRewardPerSec(address _rewardToken, uint256 _rewardPerSec) external onlyOwner {
    LibDoublyLinkedList.List storage rewardPerSecList = LibMoneyMarket01
      .moneyMarketDiamondStorage()
      .borrowingRewardPerSecList;
    if (rewardPerSecList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      rewardPerSecList.init();
    }
    rewardPerSecList.add(_rewardToken, _rewardPerSec);

    emit LogAddRewardPerSec(_rewardToken, _rewardPerSec);
  }

  function updateBorrowingRewardPerSec(address _rewardToken, uint256 _rewardPerSec) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibDoublyLinkedList.List storage rewardPerSecList = moneyMarketDs.borrowingRewardPerSecList;
    if (rewardPerSecList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      rewardPerSecList.init();
    }

    LibBorrowingReward.massUpdatePoolInReward(_rewardToken, moneyMarketDs);

    rewardPerSecList.updateOrRemove(_rewardToken, _rewardPerSec);

    emit LogUpdateRewardPerSec(_rewardToken, _rewardPerSec);
  }

  function addLendingPool(
    address _rewardToken,
    address _token,
    uint256 _allocPoint
  ) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    if (moneyMarketDs.lendingPoolInfos[_poolKey].allocPoint > 0) revert AdminFacet_PoolIsAlreadyAdded();
    moneyMarketDs.lendingPoolInfos[_poolKey] = LibMoneyMarket01.PoolInfo({
      accRewardPerShare: 0,
      lastRewardTime: block.timestamp.toUint128(),
      allocPoint: _allocPoint.toUint128()
    });
    moneyMarketDs.totalLendingPoolAllocPoints[_rewardToken] += _allocPoint;

    // register pool in reward pool list
    LibDoublyLinkedList.List storage poolList = moneyMarketDs.rewardLendingPoolList[_rewardToken];
    if (poolList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      poolList.init();
    }
    poolList.add(_token, 1);

    emit LogAddLendingPool(_token, _rewardToken, _allocPoint);
  }

  function setLendingPool(
    address _rewardToken,
    address _token,
    uint256 _newAllocPoint
  ) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.lendingPoolInfos[_poolKey];
    uint256 _totalLendingPoolAllocPoint = moneyMarketDs.totalLendingPoolAllocPoints[_rewardToken];
    moneyMarketDs.totalLendingPoolAllocPoints[_rewardToken] +=
      _totalLendingPoolAllocPoint -
      poolInfo.allocPoint +
      _newAllocPoint;
    moneyMarketDs.lendingPoolInfos[_poolKey].allocPoint = _newAllocPoint.toUint128();

    // update pool in reward pool list
    LibDoublyLinkedList.List storage poolList = moneyMarketDs.rewardLendingPoolList[_rewardToken];
    if (poolList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      poolList.init();
    }
    poolList.updateOrRemove(_token, _newAllocPoint > 0 ? 1 : 0);

    emit LogSetLendingPool(_token, _rewardToken, _newAllocPoint);
  }

  function addBorrowingPool(
    address _rewardToken,
    address _token,
    uint256 _allocPoint
  ) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();

    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (moneyMarketDs.borrowingPoolInfos[_poolKey].allocPoint > 0) revert AdminFacet_PoolIsAlreadyAdded();
    moneyMarketDs.borrowingPoolInfos[_poolKey] = LibMoneyMarket01.PoolInfo({
      accRewardPerShare: 0,
      lastRewardTime: block.timestamp.toUint128(),
      allocPoint: _allocPoint.toUint128()
    });
    moneyMarketDs.totalBorrowingPoolAllocPoints[_rewardToken] += _allocPoint;

    // register pool in reward pool list
    LibDoublyLinkedList.List storage poolList = moneyMarketDs.rewardBorrowingPoolList[_rewardToken];
    if (poolList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      poolList.init();
    }
    poolList.add(_token, 1);

    emit LogAddBorroweringPool(_token, _rewardToken, _allocPoint);
  }

  function setBorrowingPool(
    address _rewardToken,
    address _token,
    uint256 _newAllocPoint
  ) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();

    bytes32 _poolKey = LibMoneyMarket01.getPoolKey(_rewardToken, _token);
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.borrowingPoolInfos[_poolKey];
    uint256 _totalBorrowingPoolAllocPoint = moneyMarketDs.totalBorrowingPoolAllocPoints[_rewardToken];
    moneyMarketDs.totalBorrowingPoolAllocPoints[_rewardToken] +=
      _totalBorrowingPoolAllocPoint -
      poolInfo.allocPoint +
      _newAllocPoint;
    moneyMarketDs.borrowingPoolInfos[_poolKey].allocPoint = _newAllocPoint.toUint128();

    // update pool in reward pool list
    LibDoublyLinkedList.List storage poolList = moneyMarketDs.rewardBorrowingPoolList[_rewardToken];
    if (poolList.getNextOf(LibDoublyLinkedList.START) == LibDoublyLinkedList.EMPTY) {
      poolList.init();
    }
    poolList.updateOrRemove(_token, _newAllocPoint > 0 ? 1 : 0);

    emit LogSetBorrowingPool(_token, _rewardToken, _newAllocPoint);
  }

  function setFees(
    uint256 _newLendingFeeBps,
    uint256 _newRepurchaseRewardBps,
    uint256 _newRepurchaseFeeBps,
    uint256 _newLiquidationFeeBps
  ) external onlyOwner {
    if (
      _newLendingFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newRepurchaseRewardBps > LibMoneyMarket01.MAX_BPS ||
      _newRepurchaseFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newLiquidationFeeBps > LibMoneyMarket01.MAX_BPS
    ) revert AdminFacet_BadBps();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.lendingFeeBps = _newLendingFeeBps;
    moneyMarketDs.repurchaseRewardBps = _newRepurchaseRewardBps;
    moneyMarketDs.repurchaseFeeBps = _newRepurchaseFeeBps;
    moneyMarketDs.liquidationFeeBps = _newLiquidationFeeBps;
  }
}
