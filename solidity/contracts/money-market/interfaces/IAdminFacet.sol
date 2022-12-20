// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";

interface IAdminFacet {
  // errors
  error AdminFacet_PoolIsAlreadyAdded();
  error AdminFacet_InvalidAddress();
  error AdminFacet_BadBps();
  error AdminFacet_ReserveTooLow();

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

  struct NonCollatBorrowLimitInput {
    address account;
    uint256 limit;
  }

  function setTokenToIbTokens(IbPair[] memory _ibPair) external;

  function tokenToIbTokens(address _token) external view returns (address);

  function ibTokenToTokens(address _ibToken) external view returns (address);

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setNonCollatBorrower(address _borrower, bool _isOk) external;

  function tokenConfigs(address _token) external view returns (LibMoneyMarket01.TokenConfig memory);

  function setInterestModel(address _token, address model) external;

  function setOracle(address _oracle) external;

  function setRepurchasersOk(address[] memory list, bool _isOk) external;

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external;

  function setLiquidationCallersOk(address[] calldata list, bool _isOk) external;

  function setTreasury(address newTreasury) external;

  function setNonCollatInterestModel(
    address _account,
    address _token,
    address _model
  ) external;

  function setNonCollatBorrowLimitUSDValues(NonCollatBorrowLimitInput[] memory _nonCollatBorrowLimitInputs) external;

  function setFees(
    uint256 _newLendingFeeBps,
    uint256 _newRepurchaseRewardBps,
    uint256 _newRepurchaseFeeBps,
    uint256 _newLiquidationFeeBps
  ) external;

  function getReservePool(address _token) external view returns (uint256 _reserve);

  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external;
}
