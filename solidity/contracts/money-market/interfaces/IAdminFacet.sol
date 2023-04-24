// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { LibConstant } from "../libraries/LibConstant.sol";

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
  error AdminFacet_InvalidDebtTokenImplementation();
  error AdminFacet_ExceedMaxRepurchaseReward();
  error AdminFacet_ExceedMaxNonCollatBorrowers();
  error AdminFacet_Unauthorized();

  struct IbPair {
    address token;
    address ibToken;
  }

  struct TokenConfigInput {
    LibConstant.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
  }

  struct ProtocolConfigInput {
    address account;
    TokenBorrowLimitInput[] tokenBorrowLimit;
    uint256 borrowingPowerLimit;
  }

  struct TokenBorrowLimitInput {
    address token;
    uint256 maxTokenBorrow;
  }

  struct WithdrawProtocolReserveParam {
    address token;
    address to;
    uint256 amount;
  }

  function openMarket(
    address _token,
    TokenConfigInput calldata _tokenConfigInput,
    TokenConfigInput calldata _ibTokenConfigInput
  ) external returns (address);

  function setTokenConfigs(address[] calldata _tokens, TokenConfigInput[] calldata _tokenConfigs) external;

  function setNonCollatBorrowerOk(address _borrower, bool _isOk) external;

  function setInterestModel(address _token, address model) external;

  function setOracle(address _oracle) external;

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external;

  function setAccountManagersOk(address[] calldata _list, bool _isOk) external;

  function setLiquidatorsOk(address[] calldata list, bool _isOk) external;

  function setRiskManagersOk(address[] calldata _riskManagers, bool _isOk) external;

  function setLiquidationTreasury(address newTreasury) external;

  function setNonCollatInterestModel(
    address _account,
    address _token,
    address _model
  ) external;

  function setFees(
    uint16 _newLendingFeeBps,
    uint16 _newRepurchaseFeeBps,
    uint16 _newLiquidationFeeBps
  ) external;

  function setRepurchaseRewardModel(IFeeModel _newRepurchaseRewardModel) external;

  function setIbTokenImplementation(address _newImplementation) external;

  function setDebtTokenImplementation(address _newImplementation) external;

  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInput) external;

  function setLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold) external;

  function setMaxNumOfToken(
    uint8 _numOfCollat,
    uint8 _numOfDebt,
    uint8 _numOfNonCollatDebt
  ) external;

  function topUpTokenReserve(address _token, uint256 _amount) external;

  function setMinDebtSize(uint256 _newValue) external;

  function setEmergencyPaused(bool _isPaused) external;

  function setTokenMaximumCapacities(
    address _token,
    uint256 _newMaxCollateral,
    uint256 _newMaxBorrow
  ) external;

  function withdrawProtocolReserves(WithdrawProtocolReserveParam[] calldata _withdrawProtocolReserveParam) external;
}
