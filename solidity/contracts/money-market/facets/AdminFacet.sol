// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

// interfaces
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";

contract AdminFacet is IAdminFacet {
  using SafeCast for uint256;

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
    moneyMarketDs.oracle = IPriceOracle(_oracle);
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

  function setRewardConfig(address _rewardToken, uint256 _rewardPerSecond) external onlyOwner {
    if (_rewardToken == address(0)) revert AdminFacet_InvalidAddress();
    if (_rewardPerSecond == 0) revert AdminFacet_InvalidReward();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.rewardConfig = LibMoneyMarket01.RewardConfig({
      rewardToken: _rewardToken,
      rewardPerSecond: _rewardPerSecond
    });
  }

  function setRewardDistributor(address _addr) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.rewardDistributor = _addr;
  }

  function addPool(address _token, uint256 _allocPoint) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();
    if (_allocPoint == 0) revert AdminFacet_InvalidAllocPoint();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (moneyMarketDs.poolInfos[_token].allocPoint > 0) revert AdminFacet_PoolIsAlreadyAdded();
    moneyMarketDs.poolInfos[_token] = LibMoneyMarket01.PoolInfo({
      accRewardPerShare: 0,
      lastRewardTime: block.timestamp.toUint128(),
      allocPoint: _allocPoint.toUint128()
    });
    moneyMarketDs.totalAllocPoint += _allocPoint;
  }

  function setPool(address _token, uint256 _newAllocPoint) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();
    if (_newAllocPoint == 0) revert AdminFacet_InvalidAllocPoint();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.poolInfos[_token];
    uint256 _totalAllocPoint = moneyMarketDs.totalAllocPoint;
    moneyMarketDs.totalAllocPoint += _totalAllocPoint - poolInfo.allocPoint + _newAllocPoint;
    moneyMarketDs.poolInfos[_token].allocPoint = _newAllocPoint.toUint128();
  }

  function addBorrowerPool(address _token, uint256 _allocPoint) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();
    if (_allocPoint == 0) revert AdminFacet_InvalidAllocPoint();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (moneyMarketDs.borrowerPoolInfos[_token].allocPoint > 0) revert AdminFacet_PoolIsAlreadyAdded();
    moneyMarketDs.borrowerPoolInfos[_token] = LibMoneyMarket01.PoolInfo({
      accRewardPerShare: 0,
      lastRewardTime: block.timestamp.toUint128(),
      allocPoint: _allocPoint.toUint128()
    });
    moneyMarketDs.totalBorrowerPoolAllocPoint += _allocPoint;
  }

  function setBorrowerPool(address _token, uint256 _newAllocPoint) external onlyOwner {
    if (_token == address(0)) revert AdminFacet_InvalidAddress();
    if (_newAllocPoint == 0) revert AdminFacet_InvalidAllocPoint();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.PoolInfo memory poolInfo = moneyMarketDs.borrowerPoolInfos[_token];
    uint256 _totalBorrowerPoolAllocPoint = moneyMarketDs.totalBorrowerPoolAllocPoint;
    moneyMarketDs.totalBorrowerPoolAllocPoint += _totalBorrowerPoolAllocPoint - poolInfo.allocPoint + _newAllocPoint;
    moneyMarketDs.borrowerPoolInfos[_token].allocPoint = _newAllocPoint.toUint128();
  }
}
