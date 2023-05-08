// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibConstant } from "../libraries/LibConstant.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// ---- Interfaces ---- //
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IFeeModel } from "../interfaces/IFeeModel.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";
import { IDebtToken } from "../interfaces/IDebtToken.sol";
import { IMiniFL } from "../interfaces/IMiniFL.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title AdminFacet is dedicated to protocol parameter configuration
contract AdminFacet is IAdminFacet {
  using LibSafeToken for IERC20;
  using SafeCast for uint256;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  mapping(address => bool) public whitelistedCallers;

  event LogOpenMarket(address indexed _user, address indexed _token, address _ibToken, address _debtToken);
  event LogSetTokenConfig(address indexed _token, LibConstant.TokenConfig _config);
  event LogsetNonCollatBorrowerOk(address indexed _account, bool isOk);
  event LogSetInterestModel(address indexed _token, address _interestModel);
  event LogSetNonCollatInterestModel(address indexed _account, address indexed _token, address _interestModel);
  event LogSetOracle(address _oracle);
  event LogSetLiquidationStratOk(address indexed _strat, bool isOk);
  event LogSetLiquidatorOk(address indexed _account, bool isOk);
  event LogSetRiskManagerOk(address indexed _account, bool isOk);
  event LogSetAccountManagerOk(address indexed _manager, bool isOk);
  event LogSetLiquidationTreasury(address indexed _treasury);
  event LogSetFees(uint256 _lendingFeeBps, uint256 _repurchaseFeeBps, uint256 _liquidationFeeBps);
  event LogSetFlashloanFees(uint256 _flashloanFeeBps, uint256 _lenderFlashloanBps);
  event LogSetRepurchaseRewardModel(IFeeModel indexed _repurchaseRewardModel);
  event LogSetIbTokenImplementation(address indexed _newImplementation);
  event LogSetDebtTokenImplementation(address indexed _newImplementation);
  event LogSetProtocolTokenBorrowLimit(address indexed _account, address indexed _token, uint256 maxTokenBorrow);
  event LogSetProtocolConfig(address _account, uint256 _borrowingPowerLimit);
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);
  event LogSetMaxNumOfToken(uint8 _maxNumOfCollat, uint8 _maxNumOfDebt, uint8 _maxNumOfOverCollatDebt);
  event LogSetLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold);
  event LogTopUpTokenReserve(address indexed _token, uint256 _amount);
  event LogSetMinDebtSize(uint256 _newValue);
  event LogSetEmergencyPaused(address indexed _caller, bool _isPasued);
  event LogSetWhitelistedCaller(address indexed _caller, bool _allow);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  /// @dev allow only whitelised callers
  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert AdminFacet_Unauthorized();
    }
    _;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Open a new market for new token
  /// @param _token The token for lending/borrowing
  /// @param _tokenConfigInput Initial config for underlying token
  /// @param _ibTokenConfigInput Initial config for the new ib token
  /// @return _newIbToken The address of interest bearing token created for this market
  function openMarket(
    address _token,
    TokenConfigInput calldata _tokenConfigInput,
    TokenConfigInput calldata _ibTokenConfigInput
  ) external onlyOwner nonReentrant returns (address _newIbToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    IMiniFL _miniFL = moneyMarketDs.miniFL;

    if (moneyMarketDs.ibTokenImplementation == address(0)) {
      revert AdminFacet_InvalidIbTokenImplementation();
    }
    if (moneyMarketDs.debtTokenImplementation == address(0)) {
      revert AdminFacet_InvalidDebtTokenImplementation();
    }

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];
    address _debtToken = moneyMarketDs.tokenToDebtTokens[_token];

    // Revert if market already exist (ibToken or debtToken exist for underlyingToken)
    if (_ibToken != address(0)) {
      revert AdminFacet_InvalidToken(_token);
    }
    if (_debtToken != address(0)) {
      revert AdminFacet_InvalidToken(_token);
    }

    // Deploy new ibToken and debtToken with EIP-1167 minimal proxy to save gas
    _newIbToken = Clones.clone(moneyMarketDs.ibTokenImplementation);
    IInterestBearingToken(_newIbToken).initialize(_token, address(this));

    address _newDebtToken = Clones.clone(moneyMarketDs.debtTokenImplementation);
    IDebtToken(_newDebtToken).initialize(_token, address(this));

    // Allow MoneyMarket and MiniFL to hold debt token by adding them as okHolders
    // Since we only allow whitelisted address to hold debtToken
    address[] memory _okHolders = new address[](2);
    _okHolders[0] = address(this);
    _okHolders[1] = address(_miniFL);
    IDebtToken(_newDebtToken).setOkHolders(_okHolders, true);

    // Set tokenConfig for underlyingToken and the new ibToken
    _setTokenConfig(_token, _tokenConfigInput, moneyMarketDs);
    _setTokenConfig(_newIbToken, _ibTokenConfigInput, moneyMarketDs);

    // Associate underlyingToken with the newly created ibToken and debtToken
    moneyMarketDs.tokenToIbTokens[_token] = _newIbToken;
    moneyMarketDs.ibTokenToTokens[_newIbToken] = _token;
    moneyMarketDs.tokenToDebtTokens[_token] = _newDebtToken;

    // Create empty MiniFL pool for ibToken and debtToken
    // To simplify MoneyMarket operations we make sure that every market has pools associate with it
    // If we want to distribute reward we can set rewarder later
    // skip `massUpdatePools` to save gas since we didn't modify allocPoint
    moneyMarketDs.miniFLPoolIds[_newIbToken] = _miniFL.addPool(0, _newIbToken, false);
    moneyMarketDs.miniFLPoolIds[_newDebtToken] = _miniFL.addPool(0, _newDebtToken, false);

    emit LogOpenMarket(msg.sender, _token, _newIbToken, _newDebtToken);
  }

  /// @notice Set token-specific configuration
  /// @param _tokens Array of token to set config for
  /// @param _tokenConfigInputs Array of struct of parameters for the token, ordering should match `_tokens`
  function setTokenConfigs(address[] calldata _tokens, TokenConfigInput[] calldata _tokenConfigInputs)
    external
    onlyOwner
  {
    // Revert if tokens and inputs length mismatch
    if (_tokens.length != _tokenConfigInputs.length) {
      revert AdminFacet_InvalidArguments();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _inputLength = _tokenConfigInputs.length;
    for (uint256 _i; _i < _inputLength; ) {
      _setTokenConfig(_tokens[_i], _tokenConfigInputs[_i], moneyMarketDs);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the maximum capacities of token
  /// @param _token The token to set
  /// @param _newMaxCollateral The maximum capacity of this token as collateral
  /// @param _newMaxBorrow The maximum capacity to borrow this token
  function setTokenMaximumCapacities(
    address _token,
    uint256 _newMaxCollateral,
    uint256 _newMaxBorrow
  ) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (!moneyMarketDs.riskManagersOk[msg.sender]) {
      revert AdminFacet_Unauthorized();
    }

    if (_newMaxCollateral > 1e40) // Prevent user add collat or borrow too much
    {
      revert AdminFacet_InvalidArguments();
    }
    if (_newMaxBorrow > 1e40) {
      revert AdminFacet_InvalidArguments();
    }
    LibConstant.TokenConfig storage tokenConfig = moneyMarketDs.tokenConfigs[_token];
    tokenConfig.maxCollateral = _newMaxCollateral;
    tokenConfig.maxBorrow = _newMaxBorrow;

    emit LogSetTokenConfig(_token, tokenConfig);
  }

  function _setTokenConfig(
    address _token,
    TokenConfigInput memory _tokenConfigInput,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // Revert if factors exceed MAX_BPS
    if (
      _tokenConfigInput.collateralFactor > LibConstant.MAX_BPS ||
      _tokenConfigInput.borrowingFactor > LibConstant.MAX_BPS
    ) {
      revert AdminFacet_InvalidArguments();
    }
    // borrowingFactor can't be zero otherwise will cause divide by zero error
    if (_tokenConfigInput.borrowingFactor == 0) {
      revert AdminFacet_InvalidArguments();
    }
    // Prevent user add collat or borrow too much
    if (_tokenConfigInput.maxCollateral > 1e40) {
      revert AdminFacet_InvalidArguments();
    }
    if (_tokenConfigInput.maxBorrow > 1e40) {
      revert AdminFacet_InvalidArguments();
    }

    LibConstant.TokenConfig memory _tokenConfig = LibConstant.TokenConfig({
      tier: _tokenConfigInput.tier,
      collateralFactor: _tokenConfigInput.collateralFactor,
      borrowingFactor: _tokenConfigInput.borrowingFactor,
      maxCollateral: _tokenConfigInput.maxCollateral,
      maxBorrow: _tokenConfigInput.maxBorrow,
      to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_token)
    });

    moneyMarketDs.tokenConfigs[_token] = _tokenConfig;

    emit LogSetTokenConfig(_token, _tokenConfig);
  }

  /// @notice Whitelist/Blacklist the non collateralized borrower
  /// @param _borrower The address of contract to put in the list
  /// @param _isOk A flag to determine if allowed or not
  function setNonCollatBorrowerOk(address _borrower, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (moneyMarketDs.countNonCollatBorrowers > 5) {
      revert AdminFacet_ExceedMaxNonCollatBorrowers();
    }
    // if adding the borrower to the whitelist, increase the count
    if (_isOk) {
      if (!moneyMarketDs.nonCollatBorrowerOk[_borrower]) {
        moneyMarketDs.countNonCollatBorrowers++;
      }
      // else, decrease the count
    } else {
      if (moneyMarketDs.nonCollatBorrowerOk[_borrower]) {
        moneyMarketDs.countNonCollatBorrowers--;
      }
    }

    moneyMarketDs.nonCollatBorrowerOk[_borrower] = _isOk;
    emit LogsetNonCollatBorrowerOk(_borrower, _isOk);
  }

  /// @notice Set the interest model for a token specifically to over collateralized borrowing
  /// @param _token The token that the interest model will be imposed on
  /// @param _model The contract address of the interest model
  function setInterestModel(address _token, address _model) external onlyOwner {
    // Sanity check
    IInterestRateModel(_model).getInterestRate(0, 0);

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.interestModels[_token] = IInterestRateModel(_model);
    emit LogSetInterestModel(_token, _model);
  }

  /// @notice Set the interest model for a token specifically on a non collateralized borrower
  /// @param _account The address of borrower
  /// @param _token The token that the interest model will be impsoed on
  /// @param _model The contract address of the interest model
  function setNonCollatInterestModel(
    address _account,
    address _token,
    address _model
  ) external onlyOwner {
    // sanity call to IInterestRateModel
    // should revert if the address doesn't implement IInterestRateModel
    // neglect the fact if the _model implement fallback and did not revert
    IInterestRateModel(_model).getInterestRate(0, 0);

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.nonCollatInterestModels[_account][_token] = IInterestRateModel(_model);
    emit LogSetNonCollatInterestModel(_account, _token, _model);
  }

  /// @notice Set the oracle used in token pricing
  /// @param _oracle The address of oracle
  function setOracle(address _oracle) external onlyOwner {
    // Sanity check
    IAlpacaV2Oracle(_oracle).dollarToLp(0, address(0));
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.oracle = IAlpacaV2Oracle(_oracle);
    emit LogSetOracle(_oracle);
  }

  /// @notice Whitelist/Blacklist the strategy contract used in liquidation
  /// @param _strats an array of liquidation strategy contract
  /// @param _isOk a flag to allow or disallow
  function setLiquidationStratsOk(address[] calldata _strats, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _strats.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.liquidationStratOk[_strats[_i]] = _isOk;
      emit LogSetLiquidationStratOk(_strats[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Whitelist/Blacklist the address allowed for setting risk parameters
  /// @param _riskManagers an array of address of risk managers
  /// @param _isOk a flag to allow or disallow
  function setRiskManagersOk(address[] calldata _riskManagers, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _riskManagers.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.riskManagersOk[_riskManagers[_i]] = _isOk;
      emit LogSetRiskManagerOk(_riskManagers[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Whitelist/Blacklist the address allowed for liquidation
  /// @param _liquidators an array of address of liquidators
  /// @param _isOk a flag to allow or disallow
  function setLiquidatorsOk(address[] calldata _liquidators, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _liquidators.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.liquidatorsOk[_liquidators[_i]] = _isOk;
      emit LogSetLiquidatorOk(_liquidators[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Whitelist/Blacklist the address allowed for interacting with money market on users' behalf
  /// @param _accountManagers an array of address of account managers
  /// @param _isOk a flag to allow or disallow
  function setAccountManagersOk(address[] calldata _accountManagers, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _accountManagers.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.accountManagersOk[_accountManagers[_i]] = _isOk;
      emit LogSetAccountManagerOk(_accountManagers[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the treasury address
  /// @param _treasury The new treasury address
  function setLiquidationTreasury(address _treasury) external onlyOwner {
    if (_treasury == address(0)) {
      revert AdminFacet_InvalidAddress();
    }
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.liquidationTreasury = _treasury;
    emit LogSetLiquidationTreasury(_treasury);
  }

  /// @notice Set protocol's fees
  /// @param _newLendingFeeBps The lending fee imposed on interest collected
  /// @param _newRepurchaseFeeBps The repurchase fee collected by the protocol
  /// @param _newLiquidationFeeBps The total fee from liquidation
  function setFees(
    uint16 _newLendingFeeBps,
    uint16 _newRepurchaseFeeBps,
    uint16 _newLiquidationFeeBps
  ) external onlyOwner {
    // Revert if fees exceed max bps
    if (
      _newLendingFeeBps > LibConstant.MAX_BPS ||
      _newRepurchaseFeeBps > LibConstant.MAX_BPS ||
      _newLiquidationFeeBps > LibConstant.MAX_BPS
    ) {
      revert AdminFacet_InvalidArguments();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // Replace existing fees
    moneyMarketDs.lendingFeeBps = _newLendingFeeBps;
    moneyMarketDs.repurchaseFeeBps = _newRepurchaseFeeBps;
    moneyMarketDs.liquidationFeeBps = _newLiquidationFeeBps;

    emit LogSetFees(_newLendingFeeBps, _newRepurchaseFeeBps, _newLiquidationFeeBps);
  }

  /// @notice Set lender portion and flashloan fee
  /// @param _flashloanFeeBps the flashloan fee collected by protocol
  /// @param _lenderFlashloanBps the portion that lenders will receive from _flashloanFeeBps
  function setFlashloanFees(uint16 _flashloanFeeBps, uint16 _lenderFlashloanBps) external onlyOwner {
    if (_flashloanFeeBps > LibConstant.MAX_BPS || _lenderFlashloanBps > LibConstant.MAX_BPS) {
      revert AdminFacet_InvalidArguments();
    }
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // Replace existing fees
    moneyMarketDs.flashloanFeeBps = _flashloanFeeBps;
    moneyMarketDs.lenderFlashloanBps = _lenderFlashloanBps;

    emit LogSetFlashloanFees(_flashloanFeeBps, _lenderFlashloanBps);
  }

  /// @notice Set the repurchase reward model for a token specifically to over collateralized borrowing
  /// @param _newRepurchaseRewardModel The contract address of the repurchase reward model
  function setRepurchaseRewardModel(IFeeModel _newRepurchaseRewardModel) external onlyOwner {
    // Sanity check
    if (LibMoneyMarket01.MAX_REPURCHASE_FEE_BPS < _newRepurchaseRewardModel.getFeeBps(1, 1000)) {
      revert AdminFacet_ExceedMaxRepurchaseReward();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.repurchaseRewardModel = _newRepurchaseRewardModel;

    emit LogSetRepurchaseRewardModel(_newRepurchaseRewardModel);
  }

  /// @notice Set the implementation address of interest bearing token
  /// @param _newImplementation The address of interest bearing contract
  function setIbTokenImplementation(address _newImplementation) external onlyOwner {
    // sanity check
    IInterestBearingToken(_newImplementation).decimals();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.ibTokenImplementation = _newImplementation;
    emit LogSetIbTokenImplementation(_newImplementation);
  }

  /// @notice Set the implementation address of debt token
  /// @param _newImplementation The address of debt token contract
  function setDebtTokenImplementation(address _newImplementation) external onlyOwner {
    // sanity check
    IDebtToken(_newImplementation).decimals();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.debtTokenImplementation = _newImplementation;
    emit LogSetDebtTokenImplementation(_newImplementation);
  }

  /// @notice Set the non collteral's borrower configuration
  /// @param _protocolConfigInputs An array of configrations for borrowers
  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _protocolConfigInputs.length;
    ProtocolConfigInput memory _protocolConfigInput;
    TokenBorrowLimitInput memory _tokenBorrowLimit;
    LibMoneyMarket01.ProtocolConfig storage protocolConfig;
    uint256 _tokenBorrowLimitLength;

    for (uint256 _i; _i < _length; ) {
      _protocolConfigInput = _protocolConfigInputs[_i];

      protocolConfig = moneyMarketDs.protocolConfigs[_protocolConfigInput.account];
      // set total borrow limit in usd for a protocol
      protocolConfig.borrowingPowerLimit = _protocolConfigInput.borrowingPowerLimit;

      // set per token borrow limit
      _tokenBorrowLimitLength = _protocolConfigInput.tokenBorrowLimit.length;
      for (uint256 _j; _j < _tokenBorrowLimitLength; ) {
        _tokenBorrowLimit = _protocolConfigInput.tokenBorrowLimit[_j];
        protocolConfig.maxTokenBorrow[_tokenBorrowLimit.token] = _tokenBorrowLimit.maxTokenBorrow;

        emit LogSetProtocolTokenBorrowLimit(
          _protocolConfigInput.account,
          _tokenBorrowLimit.token,
          _tokenBorrowLimit.maxTokenBorrow
        );
        unchecked {
          ++_j;
        }
      }
      emit LogSetProtocolConfig(_protocolConfigInput.account, _protocolConfigInput.borrowingPowerLimit);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the liquidation configuration
  /// @param _newMaxLiquidateBps The maximum percentage allowed in a single repurchase/liquidation call
  /// @param _newLiquidationThreshold The threshold that need to reach to allow liquidation
  function setLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold) external onlyOwner {
    // Revert if `_newMaxLiquidateBps` exceed max bps because can't liquidate more than full position (100%)
    // Revert if `_newLiquidationThreshold` is less than max bps because if it is less than max bps would allow to liquidation to happen before repurchase
    if (_newMaxLiquidateBps > LibConstant.MAX_BPS || _newLiquidationThreshold < LibConstant.MAX_BPS) {
      revert AdminFacet_InvalidArguments();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.maxLiquidateBps = _newMaxLiquidateBps;
    moneyMarketDs.liquidationThresholdBps = _newLiquidationThreshold;

    emit LogSetLiquidationParams(_newMaxLiquidateBps, _newLiquidationThreshold);
  }

  /// @notice Set the maximum number of collateral/borrowed
  /// @param _numOfCollat The maximum number of collateral per subaccount
  /// @param _numOfDebt The maximum number of borrowed per subaccount
  /// @param _numOfNonCollatDebt The maximum number of borrowed per non collateralized borrower
  function setMaxNumOfToken(
    uint8 _numOfCollat,
    uint8 _numOfDebt,
    uint8 _numOfNonCollatDebt
  ) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.maxNumOfCollatPerSubAccount = _numOfCollat;
    moneyMarketDs.maxNumOfDebtPerSubAccount = _numOfDebt;
    moneyMarketDs.maxNumOfDebtPerNonCollatAccount = _numOfNonCollatDebt;

    emit LogSetMaxNumOfToken(_numOfCollat, _numOfDebt, _numOfNonCollatDebt);
  }

  /// @notice Set the minimum debt size (USD) that subaccount must maintain during borrow and repay
  /// @param _newValue New minDebtSize value (USD) to be set
  function setMinDebtSize(uint256 _newValue) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.minDebtSize = _newValue;

    emit LogSetMinDebtSize(_newValue);
  }

  /// @notice Transfer token to diamond to increase token reserves
  /// @param _token token to increase reserve for
  /// @param _amount amount to transfer to diamond and increase reserve
  function topUpTokenReserve(address _token, uint256 _amount) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    // Prevent topup token that didn't have market
    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) revert AdminFacet_InvalidToken(_token);

    // Allow topup for token that has fee on transfer
    uint256 _actualAmountReceived = LibMoneyMarket01.unsafePullTokens(_token, msg.sender, _amount);
    moneyMarketDs.reserves[_token] += _actualAmountReceived;

    emit LogTopUpTokenReserve(_token, _actualAmountReceived);
  }

  /// @notice Set emerygency flag for pausing deposit and borrow
  /// @param _isPaused Flag to pause or resume
  function setEmergencyPaused(bool _isPaused) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.emergencyPaused = _isPaused;

    emit LogSetEmergencyPaused(msg.sender, _isPaused);
  }

  /// @notice Set whitelisted callers
  /// @param _callers The addresses of the callers that are going to be whitelisted.
  /// @param _allow Whether to allow or disallow callers.
  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i; _i < _length; ) {
      whitelistedCallers[_callers[_i]] = _allow;
      emit LogSetWhitelistedCaller(_callers[_i], _allow);

      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Withdraw the protocol reserves
  /// @param _withdrawProtocolReserveParam An array of protocol's reserve to withdraw
  function withdrawProtocolReserves(WithdrawProtocolReserveParam[] calldata _withdrawProtocolReserveParam)
    external
    onlyWhitelisted
  {
    uint256 _length = _withdrawProtocolReserveParam.length;
    for (uint256 _i; _i < _length; ) {
      _withdrawProtocolReserve(
        _withdrawProtocolReserveParam[_i].token,
        _withdrawProtocolReserveParam[_i].to,
        _withdrawProtocolReserveParam[_i].amount
      );

      unchecked {
        ++_i;
      }
    }
  }

  function _withdrawProtocolReserve(
    address _token,
    address _to,
    uint256 _amount
  ) internal {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // Revert if trying to withdraw more than protocolReserves
    if (_amount > moneyMarketDs.protocolReserves[_token]) {
      revert AdminFacet_ReserveTooLow();
    }
    // Revert if trying to withdraw more than actual token available even protocolReserves is enough
    if (_amount > moneyMarketDs.reserves[_token]) {
      revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    }

    // Reduce protocolReserves and reserves by amount withdrawn
    moneyMarketDs.protocolReserves[_token] -= _amount;
    moneyMarketDs.reserves[_token] -= _amount;

    IERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
  }
}
