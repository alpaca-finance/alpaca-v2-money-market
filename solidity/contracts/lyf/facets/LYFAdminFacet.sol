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

/// @title LYFAdminFacet is dedicated to protocol parameter configuration
contract LYFAdminFacet is ILYFAdminFacet {
  using LibSafeToken for IERC20;

  event LogSetOracle(address indexed _oracle);
  event LogSetTokenConfig(address indexed _token, LibLYF01.TokenConfig _config);
  event LogSetMoneyMarket(address indexed _moneyMarket);
  event LogSetLPConfig(address indexed _lpToken, LibLYF01.LPConfig _config);
  event LogSetDebtPoolId(address indexed _token, address indexed _lpToken, uint256 _debtPoolId);
  event LogSetDebtPoolInterestModel(uint256 indexed _debtPoolId, address _interestModel);
  event LogSetMinDebtSize(uint256 _newValue);
  event LogSetReinvestorOk(address indexed _reinvester, bool isOk);
  event LogSetLiquidationStratOk(address indexed _liquidationStrat, bool isOk);
  event LogSetLiquidatorsOk(address indexed _liquidator, bool isOk);
  event LogSetLiquidationTreasury(address indexed _treasury);
  event LogSetRevenueTreasury(address indexed _treasury);
  event LogSetMaxNumOfToken(uint256 _maxNumOfCollat, uint256 _maxNumOfDebt);
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);
  event LogSetRewardConversionConfigs(address indexed _rewardToken, LibLYF01.RewardConversionConfig _config);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  /// @notice Set the oracle used in token pricing
  /// @param _oracle The address of oracle
  function setOracle(address _oracle) external onlyOwner {
    // sanity check
    IAlpacaV2Oracle(_oracle).dollarToLp(0, address(0));
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = IAlpacaV2Oracle(_oracle);

    emit LogSetOracle(_oracle);
  }

  /// @notice Set token-specific configuration
  /// @param _tokenConfigInputs A struct of parameters for the token
  function setTokenConfigs(TokenConfigInput[] calldata _tokenConfigInputs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _inputLength = _tokenConfigInputs.length;
    LibLYF01.TokenConfig memory _tokenConfig;
    TokenConfigInput memory _tokenConfigInput;
    for (uint256 _i; _i < _inputLength; ) {
      _tokenConfigInput = _tokenConfigInputs[_i];
      // factors should not greater than MAX_BPS
      if (
        _tokenConfigInput.collateralFactor > LibLYF01.MAX_BPS || _tokenConfigInput.borrowingFactor > LibLYF01.MAX_BPS
      ) {
        revert LYFAdminFacet_InvalidArguments();
      }
      // borrowingFactor can't be zero otherwise will cause divide by zero error
      if (_tokenConfigInput.borrowingFactor == 0) {
        revert LYFAdminFacet_InvalidArguments();
      }
      // prevent user add collat or borrow too much
      if (_tokenConfigInput.maxCollateral > 1e40) {
        revert LYFAdminFacet_InvalidArguments();
      }

      _tokenConfig = LibLYF01.TokenConfig({
        tier: _tokenConfigInput.tier,
        collateralFactor: _tokenConfigInput.collateralFactor,
        borrowingFactor: _tokenConfigInput.borrowingFactor,
        maxCollateral: _tokenConfigInput.maxCollateral,
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_tokenConfigInput.token)
      });

      lyfDs.tokenConfigs[_tokenConfigInput.token] = _tokenConfig;

      emit LogSetTokenConfig(_tokenConfigInput.token, _tokenConfig);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set UniV2-like LP token configuration
  /// @param _lpConfigInputs A struct of parameters for the LP Token
  function setLPConfigs(LPConfigInput[] calldata _lpConfigInputs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _len = _lpConfigInputs.length;

    LibLYF01.LPConfig memory _config;
    LPConfigInput memory _input;

    for (uint256 _i; _i < _len; ) {
      _input = _lpConfigInputs[_i];
      if (_input.reinvestTreasuryBountyBps > LibLYF01.MAX_BPS) {
        revert LYFAdminFacet_InvalidArguments();
      }
      if (_input.rewardToken != _input.reinvestPath[0]) {
        revert LYFAdminFacet_InvalidArguments();
      }

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

  /// @notice Set the association of token and lptoken and assign to debt pool
  /// @param _token The borrowing token
  /// @param _lpToken The destination LP token of borrowed token
  /// @param _debtPoolId The index for debt pool
  function setDebtPoolId(
    address _token,
    address _lpToken,
    uint256 _debtPoolId
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    LibLYF01.DebtPoolInfo storage debtPoolInfo = lyfDs.debtPoolInfos[_debtPoolId];

    // validate token must not already set
    // validate if token exist but different lp
    // _debtPoolId can't be 0 or max uint
    if (
      lyfDs.debtPoolIds[_token][_lpToken] != 0 ||
      (debtPoolInfo.token != address(0) && debtPoolInfo.token != _token) ||
      _debtPoolId == 0 ||
      _debtPoolId == type(uint256).max
    ) {
      revert LYFAdminFacet_BadDebtPoolId();
    }
    lyfDs.debtPoolIds[_token][_lpToken] = _debtPoolId;
    debtPoolInfo.token = _token;

    emit LogSetDebtPoolId(_token, _lpToken, _debtPoolId);
  }

  /// @notice Associate the Interest Model to a debt pool
  /// @param _debtPoolId The index of the debt pool
  /// @param _interestModel The address of the model interest
  function setDebtPoolInterestModel(uint256 _debtPoolId, address _interestModel) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // sanity check
    IInterestRateModel(_interestModel).getInterestRate(1, 1);

    lyfDs.debtPoolInfos[_debtPoolId].interestModel = _interestModel;

    emit LogSetDebtPoolInterestModel(_debtPoolId, _interestModel);
  }

  /// @notice Set the minimum debt size per token per subaccount
  /// @param _newMinDebtSize The new minimum debt size to update
  function setMinDebtSize(uint256 _newMinDebtSize) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.minDebtSize = _newMinDebtSize;

    emit LogSetMinDebtSize(_newMinDebtSize);
  }

  /// @notice Set the list of callers allow for reinvest function
  /// @param _reinvestors Array of address to allow or disallow
  /// @param _isOk A flag to allow or disallow
  function setReinvestorsOk(address[] calldata _reinvestors, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = _reinvestors.length;
    address _reinvester;
    for (uint256 _i; _i < _length; ) {
      _reinvester = _reinvestors[_i];
      lyfDs.reinvestorsOk[_reinvester] = _isOk;

      emit LogSetReinvestorOk(_reinvester, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Whitelist a list of strategies address allow during liquidation process
  /// @param _strategies Array of strategy addresses to allow or disallow
  /// @param _isOk A flag to allow or disallow
  function setLiquidationStratsOk(address[] calldata _strategies, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = _strategies.length;
    address _liquidationStrat;
    for (uint256 _i; _i < _length; ) {
      _liquidationStrat = _strategies[_i];
      lyfDs.liquidationStratOk[_liquidationStrat] = _isOk;

      emit LogSetLiquidationStratOk(_liquidationStrat, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the list of callers allow for initiate liquidation process
  /// @param _liquidators Array of address to allow or disallow
  /// @param _isOk A flag to allow or disallow
  function setLiquidatorsOk(address[] calldata _liquidators, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = _liquidators.length;
    address _liquidator;
    for (uint256 _i; _i < _length; ) {
      _liquidator = _liquidators[_i];
      lyfDs.liquidationCallersOk[_liquidator] = _isOk;

      emit LogSetLiquidatorsOk(_liquidator, _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the address that will keep the liqudation's fee
  /// @param _newTreasury The destination address
  function setLiquidationTreasury(address _newTreasury) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.liquidationTreasury = _newTreasury;

    emit LogSetLiquidationTreasury(_newTreasury);
  }

  /// @notice Set the address that will keep the reinvest bounty
  /// @param _newTreasury new revenue treasury address
  function setRevenueTreasury(address _newTreasury) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.revenueTreasury = _newTreasury;

    emit LogSetRevenueTreasury(_newTreasury);
  }

  /// @notice Set the maximum number of token in various lists
  /// @param _numOfCollat The maximum number of collat
  /// @param _numOfDebt The maximum number of debt
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

  function setRewardConversionConfigs(ILYFAdminFacet.SetRewardConversionConfigInput[] calldata _inputs)
    external
    onlyOwner
  {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _len = _inputs.length;
    ILYFAdminFacet.SetRewardConversionConfigInput memory _input;
    LibLYF01.RewardConversionConfig memory _config;
    for (uint256 _i; _i < _len; ) {
      _input = _inputs[_i];

      if (_input.rewardToken != _input.path[0]) {
        revert LYFAdminFacet_InvalidArguments();
      }

      // sanity check router and path
      IRouterLike(_input.router).getAmountsIn(1 ether, _input.path);

      _config = LibLYF01.RewardConversionConfig({ router: _input.router, path: _input.path });
      lyfDs.rewardConversionConfigs[_input.rewardToken] = _config;

      emit LogSetRewardConversionConfigs(_input.rewardToken, _config);

      unchecked {
        ++_i;
      }
    }
  }
}
