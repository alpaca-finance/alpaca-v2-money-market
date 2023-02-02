// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";

interface ILYFAdminFacet {
  error LYFAdminFacet_BadDebtPoolId();
  error LYFAdminFacet_ReserveTooLow();
  error LYFAdminFacet_NotEnoughToken();
  error LYFAdminFacet_InvalidArguments();
  error LYFAdminFacet_InvalidAddress();
  error LYFAdminFacet_SubAccountHealthy(address _subAccount);

  struct TokenConfigInput {
    LibLYF01.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    address token;
    uint256 maxCollateral;
  }

  struct LPConfigInput {
    address lpToken;
    address strategy;
    address masterChef;
    address router;
    address rewardToken;
    address[] reinvestPath;
    uint256 poolId;
    uint256 maxLpAmount;
    uint256 reinvestThreshold;
    uint256 reinvestTreasuryBountyBps;
  }

  struct WriteOffSubAccountDebtInput {
    address account;
    uint256 subAccountId;
    address token;
    address lpToken;
  }

  function setOracle(address _oracle) external;

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setLPConfigs(LPConfigInput[] calldata _configs) external;

  function setDebtPoolId(
    address _token,
    address _lpToken,
    uint256 _debtPoolId
  ) external;

  function setDebtPoolInterestModel(uint256 _debtPoolId, address _interestModel) external;

  function setMinDebtSize(uint256 _newValue) external;

  function setReinvestorsOk(address[] memory list, bool _isOk) external;

  function setMaxNumOfToken(uint8 _numOfCollat, uint8 _numOfDebt) external;

  function withdrawProtocolReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external;

  function setLiquidationTreasury(address _newTreasury) external;

  function setRevenueTreasury(address _newTreasury) external;
}
