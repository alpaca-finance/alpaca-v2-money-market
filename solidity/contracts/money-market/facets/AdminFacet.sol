// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";

// interfaces
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";

contract AdminFacet is IAdminFacet {
  using SafeERC20 for ERC20;
  using SafeCast for uint256;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);

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

  function getProtocolReserve(address _token) external view returns (uint256 _reserve) {
    return LibMoneyMarket01.moneyMarketDiamondStorage().protocolReserves[_token];
  }

  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_amount > moneyMarketDs.protocolReserves[_token]) {
      revert AdminFacet_ReserveTooLow();
    }
    if (_amount > moneyMarketDs.reserves[_token]) revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();

    moneyMarketDs.protocolReserves[_token] -= _amount;

    moneyMarketDs.reserves[_token] -= _amount;
    ERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
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

  function setIbTokenImplementation(address _newImplementation) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // sanity check
    IInterestBearingToken(_newImplementation).decimals();
    moneyMarketDs.ibTokenImplementation = _newImplementation;
  }

  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _protocolConfigInputs.length;
    ProtocolConfigInput memory _protocolConfigInput;

    for (uint256 _i; _i < _length; ) {
      _protocolConfigInput = _protocolConfigInputs[_i];

      LibMoneyMarket01.ProtocolConfig storage protocolConfig = moneyMarketDs.protocolConfigs[
        _protocolConfigInput.account
      ];

      protocolConfig.borrowLimitUSDValue = _protocolConfigInput.borrowLimitUSDValue;

      // set limit for each token
      uint256 _tokenBorrowLimitLength = _protocolConfigInput.tokenBorrowLimit.length;
      for (uint256 _j; _j < _tokenBorrowLimitLength; ) {
        TokenBorrowLimitInput memory _tokenBorrowLimit = _protocolConfigInput.tokenBorrowLimit[_j];
        protocolConfig.maxTokenBorrow[_tokenBorrowLimit.token] = _tokenBorrowLimit.maxTokenBorrow;

        unchecked {
          _j++;
        }
      }

      unchecked {
        _i++;
      }
    }
  }
}
