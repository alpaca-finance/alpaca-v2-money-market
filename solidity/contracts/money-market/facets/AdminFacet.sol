// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// ---- Libraries ---- //
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
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

  event LogOpenMarket(address indexed _user, address indexed _token, address _ibToken, address _debtToken);
  event LogSetTokenConfig(address indexed _token, LibMoneyMarket01.TokenConfig _config);
  event LogsetNonCollatBorrowerOk(address indexed _account, bool isOk);
  event LogSetInterestModel(address indexed _token, address _interestModel);
  event LogSetNonCollatInterestModel(address indexed _account, address indexed _token, address _interestModel);
  event LogSetOracle(address _oracle);
  event LogSetRepurchaserOk(address indexed _account, bool isOk);
  event LogSetLiquidationStratOk(address indexed _strat, bool isOk);
  event LogSetLiquidatorOk(address indexed _account, bool isOk);
  event LogSetLiquidationTreasury(address indexed _treasury);
  event LogSetFees(
    uint256 _lendingFeeBps,
    uint256 _repurchaseFeeBps,
    uint256 _liquidationFeeBps,
    uint256 _liquidationRewardBps
  );
  event LogSetRepurchaseRewardModel(IFeeModel indexed _repurchaseRewardModel);
  event LogSetIbTokenImplementation(address indexed _newImplementation);
  event LogSetDebtTokenImplementation(address indexed _newImplementation);
  event LogSetProtocolConfig(
    address indexed _account,
    address indexed _token,
    uint256 maxTokenBorrow,
    uint256 borrowLimitUSDValue
  );
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);
  event LogSetMaxNumOfToken(uint8 _maxNumOfCollat, uint8 _maxNumOfDebt, uint8 _maxNumOfOverCollatDebt);
  event LogSetLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold);
  event LogWriteOffSubAccountDebt(
    address indexed subAccount,
    address indexed token,
    uint256 debtShareWrittenOff,
    uint256 debtValueWrittenOff
  );
  event LogTopUpTokenReserve(address indexed token, uint256 amount);
  event LogSetMinDebtSize(uint256 _newValue);
  event LogSetEmergencyPaused(address indexed caller, bool _isPasued);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  /// @notice Open a new market for new token
  /// @param _token The token for lending/borrowing
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

    if (_ibToken != address(0)) {
      revert AdminFacet_InvalidToken(_token);
    }
    if (_debtToken != address(0)) {
      revert AdminFacet_InvalidToken(_token);
    }

    _newIbToken = Clones.clone(moneyMarketDs.ibTokenImplementation);
    IInterestBearingToken(_newIbToken).initialize(_token, address(this));

    address _newDebtToken = Clones.clone(moneyMarketDs.debtTokenImplementation);
    IDebtToken(_newDebtToken).initialize(_token, address(this));

    address[] memory _okHolders = new address[](2);
    _okHolders[0] = address(this);
    _okHolders[1] = address(address(_miniFL));
    IDebtToken(_newDebtToken).setOkHolders(_okHolders, true);

    _setTokenConfig(_token, _tokenConfigInput, moneyMarketDs);
    _setTokenConfig(_newIbToken, _ibTokenConfigInput, moneyMarketDs);

    moneyMarketDs.tokenToIbTokens[_token] = _newIbToken;
    moneyMarketDs.ibTokenToTokens[_newIbToken] = _token;
    moneyMarketDs.tokenToDebtTokens[_token] = _newDebtToken;

    moneyMarketDs.miniFLPoolIds[_newIbToken] = _miniFL.addPool(0, _newIbToken, false);
    moneyMarketDs.miniFLPoolIds[_newDebtToken] = _miniFL.addPool(0, _newDebtToken, false);

    emit LogOpenMarket(msg.sender, _token, _newIbToken, _newDebtToken);
  }

  /// @notice Set token-specific configuration
  /// @param _tokenConfigInputs A struct of parameters for the token
  function setTokenConfigs(TokenConfigInput[] calldata _tokenConfigInputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _inputLength = _tokenConfigInputs.length;
    for (uint256 _i; _i < _inputLength; ) {
      _setTokenConfig(_tokenConfigInputs[_i].token, _tokenConfigInputs[_i], moneyMarketDs);

      unchecked {
        ++_i;
      }
    }
  }

  function _setTokenConfig(
    address _token,
    TokenConfigInput memory _tokenConfigInput,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    // factors should not greater than MAX_BPS
    if (
      _tokenConfigInput.collateralFactor > LibMoneyMarket01.MAX_BPS ||
      _tokenConfigInput.borrowingFactor > LibMoneyMarket01.MAX_BPS
    ) {
      revert AdminFacet_InvalidArguments();
    }
    // borrowingFactor can't be zero otherwise will cause divide by zero error
    if (_tokenConfigInput.borrowingFactor == 0) {
      revert AdminFacet_InvalidArguments();
    }
    // prevent user add collat or borrow too much
    if (_tokenConfigInput.maxCollateral > 1e40) {
      revert AdminFacet_InvalidArguments();
    }
    if (_tokenConfigInput.maxBorrow > 1e40) {
      revert AdminFacet_InvalidArguments();
    }

    LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01.TokenConfig({
      tier: _tokenConfigInput.tier,
      collateralFactor: _tokenConfigInput.collateralFactor,
      borrowingFactor: _tokenConfigInput.borrowingFactor,
      maxCollateral: _tokenConfigInput.maxCollateral,
      maxBorrow: _tokenConfigInput.maxBorrow,
      to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_tokenConfigInput.token)
    });

    moneyMarketDs.tokenConfigs[_token] = _tokenConfig;

    emit LogSetTokenConfig(_token, _tokenConfig);
  }

  /// @notice Whitelist/Blacklist the non collateralized borrower
  /// @param _borrower The address of contract to put in the list
  /// @param _isOk A flag to determine if allowed or not
  function setNonCollatBorrowerOk(address _borrower, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
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

  /// @notice Whitelist/Blacklist the address allowed for repurchasing
  /// @param _repurchasers an array of address of repurchasers
  /// @param _isOk a flag to allow or disallow
  function setRepurchasersOk(address[] calldata _repurchasers, bool _isOk) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _repurchasers.length;
    for (uint256 _i; _i < _length; ) {
      moneyMarketDs.repurchasersOk[_repurchasers[_i]] = _isOk;
      emit LogSetRepurchaserOk(_repurchasers[_i], _isOk);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Whitelist/Blacklist the strategy contract used in liquidation
  /// @param _strats an array of strategy contracts
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

  /// @notice Withdraw the protocol's reserve
  /// @param _token The token to be withdrawn
  /// @param _to The destination address
  /// @param _amount The amount to withdraw
  function withdrawProtocolReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_amount > moneyMarketDs.protocolReserves[_token]) {
      revert AdminFacet_ReserveTooLow();
    }
    if (_amount > moneyMarketDs.reserves[_token]) {
      revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    }

    moneyMarketDs.protocolReserves[_token] -= _amount;

    moneyMarketDs.reserves[_token] -= _amount;
    IERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
  }

  /// @notice Set protocol's fees
  /// @param _newLendingFeeBps The lending fee imposed on interest collected
  /// @param _newRepurchaseFeeBps The repurchase fee collected by the protocol
  /// @param _newLiquidationFeeBps The total fee from liquidation
  /// @param _newLiquidationRewardBps The fee collected by liquidator
  function setFees(
    uint16 _newLendingFeeBps,
    uint16 _newRepurchaseFeeBps,
    uint16 _newLiquidationFeeBps,
    uint16 _newLiquidationRewardBps
  ) external onlyOwner {
    if (
      _newLendingFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newRepurchaseFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newLiquidationFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newLiquidationRewardBps > LibMoneyMarket01.MAX_BPS
    ) {
      revert AdminFacet_InvalidArguments();
    }

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.lendingFeeBps = _newLendingFeeBps;
    moneyMarketDs.repurchaseFeeBps = _newRepurchaseFeeBps;
    moneyMarketDs.liquidationFeeBps = _newLiquidationFeeBps;
    moneyMarketDs.liquidationRewardBps = _newLiquidationRewardBps;

    emit LogSetFees(_newLendingFeeBps, _newRepurchaseFeeBps, _newLiquidationFeeBps, _newLiquidationRewardBps);
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
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // sanity check
    IInterestBearingToken(_newImplementation).decimals();
    moneyMarketDs.ibTokenImplementation = _newImplementation;
    emit LogSetIbTokenImplementation(_newImplementation);
  }

  /// @notice Set the implementation address of debt token
  /// @param _newImplementation The address of debt token contract
  function setDebtTokenImplementation(address _newImplementation) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // sanity check
    IDebtToken(_newImplementation).decimals();
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

      protocolConfig.borrowLimitUSDValue = _protocolConfigInput.borrowLimitUSDValue;

      // set limit for each token
      _tokenBorrowLimitLength = _protocolConfigInput.tokenBorrowLimit.length;
      for (uint256 _j; _j < _tokenBorrowLimitLength; ) {
        _tokenBorrowLimit = _protocolConfigInput.tokenBorrowLimit[_j];
        protocolConfig.maxTokenBorrow[_tokenBorrowLimit.token] = _tokenBorrowLimit.maxTokenBorrow;

        emit LogSetProtocolConfig(
          _protocolConfigInput.account,
          _tokenBorrowLimit.token,
          _tokenBorrowLimit.maxTokenBorrow,
          _protocolConfigInput.borrowLimitUSDValue
        );
        unchecked {
          ++_j;
        }
      }
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set the liquidation configuration
  /// @param _newMaxLiquidateBps The maximum percentage allowed in a single repurchase/liquidation call
  /// @param _newLiquidationThreshold The threshold that need to reach to allow liquidation
  function setLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_newMaxLiquidateBps > LibMoneyMarket01.MAX_BPS || _newLiquidationThreshold < LibMoneyMarket01.MAX_BPS) {
      revert AdminFacet_InvalidArguments();
    }

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

  /// @notice Set the minimum debt size that subaccount must maintain during borrow and repay
  /// @param _newValue New minDebtSize value to be set
  function setMinDebtSize(uint256 _newValue) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.minDebtSize = _newValue;

    emit LogSetMinDebtSize(_newValue);
  }

  /// @notice Write off subaccount's token debt in case of bad debt by resetting outstanding debt to zero
  /// @param _inputs An array of input. Each should contain account, subAccountId, and token to write off for
  function writeOffSubAccountsDebt(WriteOffSubAccountDebtInput[] calldata _inputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    uint256 _length = _inputs.length;

    address _token;
    address _account;
    address _subAccount;
    uint256 _shareToRemove;
    uint256 _amountToRemove;

    for (uint256 i; i < _length; ) {
      _token = _inputs[i].token;
      _account = _inputs[i].account;
      _subAccount = LibMoneyMarket01.getSubAccount(_account, _inputs[i].subAccountId);

      if (moneyMarketDs.subAccountCollats[_subAccount].size != 0) {
        revert AdminFacet_SubAccountHealthy(_subAccount);
      }

      LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

      // get all subaccount token debt, calculate to value
      (_shareToRemove, _amountToRemove) = LibMoneyMarket01.getOverCollatDebtShareAndAmountOf(
        _subAccount,
        _token,
        moneyMarketDs
      );

      LibMoneyMarket01.removeOverCollatDebtFromSubAccount(
        _account,
        _subAccount,
        _token,
        _shareToRemove,
        _amountToRemove,
        moneyMarketDs
      );

      emit LogWriteOffSubAccountDebt(_subAccount, _token, _shareToRemove, _amountToRemove);

      unchecked {
        ++i;
      }
    }
  }

  /// @notice Transfer token to diamond to increase token reserves
  /// @param _token token to increase reserve for
  /// @param _amount amount to transfer to diamond and increase reserve
  function topUpTokenReserve(address _token, uint256 _amount) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    if (moneyMarketDs.tokenToIbTokens[_token] == address(0)) revert AdminFacet_InvalidToken(_token);

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
}
