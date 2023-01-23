// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../interfaces/ILYFAdminFacet.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IRouterLike } from "../interfaces/IRouterLike.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

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
  event LogSetMaxNumOfToken(uint256 _maxNumOfCollat, uint256 _maxNumOfDebt);
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function setOracle(address _oracle) external onlyOwner {
    // sanity check
    IAlpacaV2Oracle(_oracle).dollarToLp(0, address(0));
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = IAlpacaV2Oracle(_oracle);

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
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_token)
      });

      lyfDs.tokenConfigs[_token] = _tokenConfig;

      emit LogSetTokenConfig(_token, _tokenConfig);

      unchecked {
        ++_i;
      }
    }
  }

  function setLPConfigs(LPConfigInput[] calldata _configs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _len = _configs.length;

    LibLYF01.LPConfig memory _config;
    LPConfigInput memory _input;

    for (uint256 _i; _i < _len; ) {
      _input = _configs[_i];

      // sanity check reinvestPath and router
      IRouterLike(_input.router).getAmountsIn(1 ether, _input.reinvestPath);

      _config = LibLYF01.LPConfig({
        strategy: _input.strategy,
        masterChef: _input.masterChef,
        router: _input.router,
        rewardToken: _input.rewardToken,
        reinvestPath: _input.reinvestPath,
        poolId: _input.poolId,
        reinvestThreshold: _input.reinvestThreshold,
        maxLpAmount: _input.maxLpAmount,
        reinvestTreasuryBountyBps: _input.reinvestTreasuryBountyBps
      });

      lyfDs.lpConfigs[_input.lpToken] = _config;

      emit LogSetLPConfig(_input.lpToken, _config);

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

    // validate token must not already set
    // validate if token exist but different lp
    // _debtShareId can't be 0 or max uint
    if (
      lyfDs.debtShareIds[_token][_lpToken] != 0 ||
      (lyfDs.debtShareTokens[_debtShareId] != address(0) && lyfDs.debtShareTokens[_debtShareId] != _token) ||
      _debtShareId == 0 ||
      _debtShareId == type(uint256).max
    ) {
      revert LYFAdminFacet_BadDebtShareId();
    }
    lyfDs.debtShareIds[_token][_lpToken] = _debtShareId;
    lyfDs.debtShareTokens[_debtShareId] = _token;

    emit LogSetDebtShareId(_token, _lpToken, _debtShareId);
  }

  function setDebtInterestModel(uint256 _debtShareId, address _interestModel) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // sanity check
    IInterestRateModel(_interestModel).getInterestRate(1, 1);

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

  function setMaxNumOfToken(uint8 _numOfCollat, uint8 _numOfDebt) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.maxNumOfCollatPerSubAccount = _numOfCollat;
    lyfDs.maxNumOfDebtPerSubAccount = _numOfDebt;
    emit LogSetMaxNumOfToken(_numOfCollat, _numOfDebt);
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
