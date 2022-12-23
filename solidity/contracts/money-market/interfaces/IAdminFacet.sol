// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IAdminFacet {
  // errors
  error AdminFacet_PoolIsAlreadyAdded();
  error AdminFacet_InvalidAddress();
  error AdminFacet_BadBps();
  error AdminFacet_ReserveTooLow();
  error AdminFacet_InvalidArguments();

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
    uint256 maxToleranceExpiredSecond;
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

  function setIbPairs(IbPair[] memory _ibPair) external;

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setNonCollatBorrower(address _borrower, bool _isOk) external;

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
    uint256 _newLendingFeeBps,
    uint256 _newRepurchaseRewardBps,
    uint256 _newRepurchaseFeeBps,
    uint256 _newLiquidationFeeBps
  ) external;

  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external;

  function setIbTokenImplementation(address _newImplementation) external;

  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInput) external;
}
