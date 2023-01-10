// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

// ---- Interfaces ---- //
import { IFeeModel } from "../interfaces/IFeeModel.sol";

interface IAdminFacet {
  // errors
  error AdminFacet_PoolIsAlreadyAdded();
  error AdminFacet_InvalidAddress();
  error AdminFacet_ReserveTooLow();
  error AdminFacet_InvalidArguments();
  error AdminFacet_InvalidToken(address _token);
  error AdminFacet_InvalidIbTokenImplementation();
  error AdminFacet_SubAccountHealthy(address _subAccount);
  error AdminFacet_ExceedMaxRepurchaseReward();

  struct IbPair {
    address token;
    address ibToken;
  }

  struct TokenConfigInput {
    address token;
    LibMoneyMarket01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
  }

  struct ProtocolConfigInput {
    address account;
    TokenBorrowLimitInput[] tokenBorrowLimit;
    uint256 borrowLimitUSDValue;
  }

  struct TokenBorrowLimitInput {
    address token;
    uint256 maxTokenBorrow;
  }

  struct WriteOffSubAccountDebtInput {
    address account;
    uint256 subAccountId;
    address token;
  }

  function openMarket(address _token) external returns (address);

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setNonCollatBorrowerOk(address _borrower, bool _isOk) external;

  function setInterestModel(address _token, address model) external;

  function setOracle(address _oracle) external;

  function setRepurchasersOk(address[] memory list, bool _isOk) external;

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external;

  function setLiquidatorsOk(address[] calldata list, bool _isOk) external;

  function setTreasury(address newTreasury) external;

  function setNonCollatInterestModel(
    address _account,
    address _token,
    address _model
  ) external;

  function setFees(
    uint16 _newLendingFeeBps,
    uint16 _newRepurchaseRewardBps,
    uint16 _newRepurchaseFeeBps,
    uint16 _newLiquidationFeeBps
  ) external;

  function setRepurchaseRewardModel(IFeeModel _newRepurchaseRewardModel) external;

  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external;

  function setIbTokenImplementation(address _newImplementation) external;

  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInput) external;

  function setLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold) external;

  function setMaxNumOfToken(
    uint8 _numOfCollat,
    uint8 _numOfDebt,
    uint8 _numOfNonCollatDebt
  ) external;

  function writeOffSubAccountsDebt(WriteOffSubAccountDebtInput[] calldata _inputs) external;

  function topUpTokenReserve(address _token, uint256 _amount) external;

  function setMinDebtSize(uint256 _newValue) external;
}
