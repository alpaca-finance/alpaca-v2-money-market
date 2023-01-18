// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

import { ILYFAdminFacet } from "../interfaces/ILYFAdminFacet.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract LYFAdminFacet is ILYFAdminFacet {
  using LibSafeToken for IERC20;

  event LogSetOracle(address indexed _oracle);
  event LogSetTokenConfig(address indexed _token, LibLYF01.TokenConfig _config);
  event LogSetMoneyMarket(address indexed _moneyMarket);
  event LogSetLPConfig(address indexed _lpToken, LibLYF01.LPConfig _config);
  event LogSetDebtShareId(address indexed _token, address indexed _lpToken, uint256 _debtShareId);
  event LogSetDebtInterestModel(uint256 indexed _debtShareId, address _interestModel);
  event LogSetMinDebtSize(uint256 _newValue);
  event LogSetReinvestorOk(address indexed _reinvester, bool isOk);
  event LogSetLiquidationStratOk(address indexed _liquidationStrat, bool isOk);
  event LogSetLiquidatorsOk(address indexed _liquidator, bool isOk);
  event LogSetTreasury(address indexed _trasury);
  event LogSetMaxNumOfToken(uint256 _maxNumOfCollat);
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function setOracle(address _oracle) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = _oracle;

    emit LogSetOracle(_oracle);
  }

  function setTokenConfigs(TokenConfigInput[] calldata _tokenConfigs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _inputLength = _tokenConfigs.length;
    address _token;
    LibLYF01.TokenConfig memory _tokenConfig;
    for (uint256 _i; _i < _inputLength; ) {
      _token = _tokenConfigs[_i].token;
      _tokenConfig = LibLYF01.TokenConfig({
        tier: _tokenConfigs[_i].tier,
        collateralFactor: _tokenConfigs[_i].collateralFactor,
        borrowingFactor: _tokenConfigs[_i].borrowingFactor,
        maxCollateral: _tokenConfigs[_i].maxCollateral,
        maxBorrow: _tokenConfigs[_i].maxBorrow,
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_token)
      });

      lyfDs.tokenConfigs[_token] = _tokenConfig;

      emit LogSetTokenConfig(_token, _tokenConfig);

      unchecked {
        ++_i;
      }
    }
  }

  function setMoneyMarket(address _moneyMarket) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.moneyMarket = _moneyMarket;
    emit LogSetMoneyMarket(_moneyMarket);
  }

  function setLPConfigs(LPConfigInput[] calldata _configs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _len = _configs.length;
    LibLYF01.LPConfig memory _config;
    address _lpToken;
    for (uint256 _i; _i < _len; ) {
      _lpToken = _configs[_i].lpToken;
      _config = LibLYF01.LPConfig({
        strategy: _configs[_i].strategy,
        masterChef: _configs[_i].masterChef,
        router: _configs[_i].router,
        rewardToken: _configs[_i].rewardToken,
        reinvestPath: _configs[_i].reinvestPath,
        reinvestThreshold: _configs[_i].reinvestThreshold,
        poolId: _configs[_i].poolId
      });

      lyfDs.lpConfigs[_lpToken] = _config;

      emit LogSetLPConfig(_lpToken, _config);

      unchecked {
        ++_i;
      }
    }
  }

  function setDebtShareId(
    address _token,
    address _lpToken,
    uint256 _debtShareId
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // validate token must not alrready set
    // validate if token exist but different lp
    if (
      lyfDs.debtShareIds[_token][_lpToken] != 0 ||
      (lyfDs.debtShareTokens[_debtShareId] != address(0) && lyfDs.debtShareTokens[_debtShareId] != _token)
    ) {
      revert LYFAdminFacet_BadDebtShareId();
    }
    lyfDs.debtShareIds[_token][_lpToken] = _debtShareId;
    lyfDs.debtShareTokens[_debtShareId] = _token;

    emit LogSetDebtShareId(_token, _lpToken, _debtShareId);
  }

  function setDebtInterestModel(uint256 _debtShareId, address _interestModel) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.interestModels[_debtShareId] = _interestModel;
    emit LogSetDebtInterestModel(_debtShareId, _interestModel);
  }

  function setMinDebtSize(uint256 _newValue) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.minDebtSize = _newValue;

    emit LogSetMinDebtSize(_newValue);
  }

  function setReinvestorsOk(address[] memory list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    address _reinvester;
    for (uint256 _i; _i < _length; ) {
      _reinvester = list[_i];
      lyfDs.reinvestorsOk[_reinvester] = _isOk;

      emit LogSetReinvestorOk(_reinvester, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    address _liquidationStrat;
    for (uint256 _i; _i < _length; ) {
      _liquidationStrat = list[_i];
      lyfDs.liquidationStratOk[_liquidationStrat] = _isOk;

      emit LogSetLiquidationStratOk(_liquidationStrat, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  function setLiquidatorsOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    address _liquidator;
    for (uint256 _i; _i < _length; ) {
      _liquidator = list[_i];
      lyfDs.liquidationCallersOk[_liquidator] = _isOk;

      emit LogSetLiquidatorsOk(_liquidator, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  function setTreasury(address _newTreasury) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.treasury = _newTreasury;

    emit LogSetTreasury(_newTreasury);
  }

  function setMaxNumOfToken(uint8 _numOfCollat) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.maxNumOfCollatPerSubAccount = _numOfCollat;
    emit LogSetMaxNumOfToken(_numOfCollat);
  }

  /// @notice Withdraw the protocol's reserve
  /// @param _token The token to be withdrawn
  /// @param _to The destination address
  /// @param _amount The amount to withdraw
  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    if (_amount > lyfDs.protocolReserves[_token]) {
      revert LYFAdminFacet_ReserveTooLow();
    }
    if (_amount > lyfDs.reserves[_token]) {
      revert LYFAdminFacet_NotEnoughToken();
    }

    lyfDs.protocolReserves[_token] -= _amount;

    lyfDs.reserves[_token] -= _amount;
    IERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
  }
}
