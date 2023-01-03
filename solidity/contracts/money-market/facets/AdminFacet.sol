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

// ---- Interfaces ---- //
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title AdminFacet is dedicated to protocol parameter configuration
contract AdminFacet is IAdminFacet {
  using LibSafeToken for IERC20;
  using SafeCast for uint256;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogOpenMarket(address indexed _user, address indexed _token, address _ibToken);
  event LogSetTokenConfig(address indexed _token, LibMoneyMarket01.TokenConfig _config);
  event LogsetNonCollatBorrowerOk(address indexed _account, bool isOk);
  event LogSetInterestModel(address indexed _token, address _interestModel);
  event LogSetNonCollatInterestModel(address indexed _account, address indexed _token, address _interestModel);
  event LogSetOracle(address _oracle);
  event LogSetRepurchaserOk(address indexed _account, bool isOk);
  event LogSetLiquidationStratOk(address indexed _strat, bool isOk);
  event LogSetLiquidatorOk(address indexed _account, bool isOk);
  event LogSetTreasury(address indexed _treasury);
  event LogSetFees(
    uint256 lendingFeeBps,
    uint256 repurchaseRewardBps,
    uint256 repurchaseFeeBps,
    uint256 liquidationFeeBps
  );
  event LogSetIbTokenImplementation(address indexed _newImplementation);
  event LogSetProtocolConfig(
    address indexed _account,
    address indexed _token,
    uint256 maxTokenBorrow,
    uint256 borrowLimitUSDValue
  );
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);
  event LogSetMaxNumOfToken(uint8 _maxNumOfCollat, uint8 _maxNumOfDebt, uint8 _maxNumOfOverCollatDebt);
  event LogSetLiquidationParams(uint16 _newMaxLiquidateBps, uint16 _newLiquidationThreshold);
  event LogSetMinUsedBorrowingPower(uint256 _newValue);

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
  function openMarket(address _token) external onlyOwner nonReentrant returns (address _newIbToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (moneyMarketDs.ibTokenImplementation == address(0)) revert AdminFacet_InvalidIbTokenImplementation();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken != address(0)) {
      revert AdminFacet_InvalidToken(_token);
    }

    _newIbToken = Clones.clone(moneyMarketDs.ibTokenImplementation);
    IInterestBearingToken(_newIbToken).initialize(_token, address(this));

    // todo: tbd
    LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01.TokenConfig({
      tier: LibMoneyMarket01.AssetTier.ISOLATE,
      collateralFactor: 0,
      borrowingFactor: 8500,
      maxCollateral: 0,
      maxBorrow: 100e18,
      to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_token)
    });

    LibMoneyMarket01.setIbPair(_token, _newIbToken, moneyMarketDs);
    LibMoneyMarket01.setTokenConfig(_token, _tokenConfig, moneyMarketDs);

    emit LogOpenMarket(msg.sender, _token, _newIbToken);
  }

  /// @notice Set token-specific configuration
  /// @param _tokenConfigInputs A struct of parameters for the token
  function setTokenConfigs(TokenConfigInput[] calldata _tokenConfigInputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _inputLength = _tokenConfigInputs.length;
    for (uint8 _i; _i < _inputLength; ) {
      TokenConfigInput calldata _tokenConfigInput = _tokenConfigInputs[_i];
      _validateTokenConfig(
        _tokenConfigInput.collateralFactor,
        _tokenConfigInput.borrowingFactor,
        _tokenConfigInput.maxCollateral,
        _tokenConfigInput.maxBorrow
      );
      LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01.TokenConfig({
        tier: _tokenConfigInput.tier,
        collateralFactor: _tokenConfigInput.collateralFactor,
        borrowingFactor: _tokenConfigInput.borrowingFactor,
        maxCollateral: _tokenConfigInput.maxCollateral,
        maxBorrow: _tokenConfigInput.maxBorrow,
        to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_tokenConfigInput.token)
      });

      LibMoneyMarket01.setTokenConfig(_tokenConfigInput.token, _tokenConfig, moneyMarketDs);

      emit LogSetTokenConfig(_tokenConfigInput.token, _tokenConfig);

      unchecked {
        ++_i;
      }
    }
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
    // Sanity check
    IInterestRateModel(_model).getInterestRate(0, 0);

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    bytes32 _nonCollatId = LibMoneyMarket01.getNonCollatId(_account, _token);
    moneyMarketDs.nonCollatInterestModels[_nonCollatId] = IInterestRateModel(_model);
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
    for (uint8 _i; _i < _length; ) {
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
  function setTreasury(address _treasury) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.treasury = _treasury;
    emit LogSetTreasury(_treasury);
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
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    if (_amount > moneyMarketDs.protocolReserves[_token]) {
      revert AdminFacet_ReserveTooLow();
    }
    if (_amount > moneyMarketDs.reserves[_token]) revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();

    moneyMarketDs.protocolReserves[_token] -= _amount;

    moneyMarketDs.reserves[_token] -= _amount;
    IERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
  }

  /// @notice Set protocol's fees
  /// @param _newLendingFeeBps The lending fee imposed on interest collected
  /// @param _newRepurchaseRewardBps The reward bps given out to repurchaser as a premium on collateral
  /// @param _newRepurchaseFeeBps The repurchase fee collected by the protocol
  /// @param _newLiquidationFeeBps The liquidation fee collected by the protocol
  function setFees(
    uint16 _newLendingFeeBps,
    uint16 _newRepurchaseRewardBps,
    uint16 _newRepurchaseFeeBps,
    uint16 _newLiquidationFeeBps
  ) external onlyOwner {
    if (
      _newLendingFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newRepurchaseRewardBps > LibMoneyMarket01.MAX_BPS ||
      _newRepurchaseFeeBps > LibMoneyMarket01.MAX_BPS ||
      _newLiquidationFeeBps > LibMoneyMarket01.MAX_BPS
    ) revert AdminFacet_InvalidArguments();

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    moneyMarketDs.lendingFeeBps = _newLendingFeeBps;
    moneyMarketDs.repurchaseRewardBps = _newRepurchaseRewardBps;
    moneyMarketDs.repurchaseFeeBps = _newRepurchaseFeeBps;
    moneyMarketDs.liquidationFeeBps = _newLiquidationFeeBps;

    emit LogSetFees(_newLendingFeeBps, _newRepurchaseRewardBps, _newRepurchaseFeeBps, _newLiquidationFeeBps);
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

  /// @notice Set the non collteral's borrower configuration
  /// @param _protocolConfigInputs An array of configrations for borrowers
  function setProtocolConfigs(ProtocolConfigInput[] calldata _protocolConfigInputs) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    uint256 _length = _protocolConfigInputs.length;
    ProtocolConfigInput memory _protocolConfigInput;

    for (uint256 _i; _i < _length; ) {
      _protocolConfigInput = _protocolConfigInputs[_i];

      LibMoneyMarket01.ProtocolConfig storage protocolConfig = moneyMarketDs.protocolConfigs[
        _protocolConfigInput.account
      ];

      protocolConfig.borrowLimitUSDValue = _protocolConfigInput.borrowLimitUSDValue;

      // set limit for each token
      uint256 _tokenBorrowLimitLength = _protocolConfigInput.tokenBorrowLimit.length;
      for (uint256 _j; _j < _tokenBorrowLimitLength; ) {
        TokenBorrowLimitInput memory _tokenBorrowLimit = _protocolConfigInput.tokenBorrowLimit[_j];
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
    if (_newMaxLiquidateBps > LibMoneyMarket01.MAX_BPS || _newLiquidationThreshold > LibMoneyMarket01.MAX_BPS)
      revert AdminFacet_InvalidArguments();
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

  /// @notice Set the minimum used borrowing power that subaccount must maintain during borrow and repay
  /// @param _newValue New minUsedBorrowingPower value to be set
  function setMinUsedBorrowingPower(uint256 _newValue) external onlyOwner {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.minUsedBorrowingPower = _newValue;

    emit LogSetMinUsedBorrowingPower(_newValue);
  }

  function _validateTokenConfig(
    uint256 collateralFactor,
    uint256 borrowingFactor,
    uint256 maxCollateral,
    uint256 maxBorrow
  ) internal pure {
    // factors should not greater than MAX_BPS
    if (collateralFactor > LibMoneyMarket01.MAX_BPS || borrowingFactor > LibMoneyMarket01.MAX_BPS)
      revert AdminFacet_InvalidArguments();

    // prevent user add collat or borrow too much
    if (maxCollateral > 1e40) revert AdminFacet_InvalidArguments();
    if (maxBorrow > 1e40) revert AdminFacet_InvalidArguments();
  }
}
