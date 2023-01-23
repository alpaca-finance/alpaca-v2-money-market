// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibLYF01 } from "../libraries/LibLYF01.sol";

interface ILYFAdminFacet {
  error LYFAdminFacet_BadDebtShareId();
  error LYFAdminFacet_ReserveTooLow();
  error LYFAdminFacet_NotEnoughToken();

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
    uint256 reinvestThreshold;
    uint256 poolId;
    uint256 globalMaxCollatAmount;
  }

  function setOracle(address _oracle) external;

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external;

  function setLPConfigs(LPConfigInput[] calldata _configs) external;

  function setDebtShareId(
    address _token,
    address _lpToken,
    uint256 _debtShareId
  ) external;

  function setDebtInterestModel(uint256 _debtShareId, address _interestModel) external;

  function setMinDebtSize(uint256 _newValue) external;

  function setReinvestorsOk(address[] memory list, bool _isOk) external;

  function setMaxNumOfToken(uint8 _numOfCollat, uint8 _numOfDebt) external;

  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external;
}
