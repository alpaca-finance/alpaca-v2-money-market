// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IWNative } from "../interfaces/IWNative.sol";
import { IWNativeRelayer } from "../interfaces/IWNativeRelayer.sol";

import { IbToken } from "../IbToken.sol";

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract LendFacet is ILendFacet {
  using SafeERC20 for ERC20;
  using LibSafeToken for address;

  event LogDeposit(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogWithdraw(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogOpenMarket(address indexed _user, address indexed _token, address _ibToken);
  event LogDepositETH(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);
  event LogWithdrawETH(address indexed _user, address _token, address _ibToken, uint256 _amountIn, uint256 _amountOut);

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  // open isolate token market, able to borrow only
  function openMarket(address _token) external nonReentrant returns (address _newIbToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken != address(0)) {
      revert LendFacet_InvalidToken(_token);
    }

    string memory _tokenSymbol = IERC20(_token).symbol();
    uint8 _tokenDecimals = IERC20(_token).decimals();
    _newIbToken = address(
      new IbToken(string.concat("Interest Bearing ", _tokenSymbol), string.concat("IB", _tokenSymbol), _tokenDecimals)
    );

    // todo: tbd
    LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01.TokenConfig({
      tier: LibMoneyMarket01.AssetTier.ISOLATE,
      collateralFactor: 0,
      borrowingFactor: 8500,
      maxCollateral: 0,
      maxBorrow: 100e18,
      maxToleranceExpiredSecond: 86400,
      to18ConversionFactor: LibMoneyMarket01.to18ConversionFactor(_token)
    });

    LibMoneyMarket01.setIbPair(_token, _newIbToken, moneyMarketDs);
    LibMoneyMarket01.setTokenConfig(_token, _tokenConfig, moneyMarketDs);

    emit LogOpenMarket(msg.sender, _token, _newIbToken);
  }

  function deposit(address _token, uint256 _amount) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    LibMoneyMarket01.accureInterest(_token, moneyMarketDs);

    (address _ibToken, uint256 _shareToMint) = _getShareToMint(_token, _amount, moneyMarketDs);

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IbToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _shareToMint);
  }

  function withdraw(address _ibToken, uint256 _shareAmount) external nonReentrant returns (uint256 _shareValue) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    _shareValue = LibMoneyMarket01.withdraw(_ibToken, _shareAmount, msg.sender, moneyMarketDs);
  }

  function depositETH() external payable nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _nativeToken = moneyMarketDs.nativeToken;
    uint256 _amount = msg.value;
    if (_nativeToken == address(0)) revert LendFacet_InvalidToken(_nativeToken);
    if (_amount == 0) revert LendFacet_InvalidAmount(_amount);
    LibMoneyMarket01.accureInterest(_nativeToken, moneyMarketDs);

    (address _ibToken, uint256 _shareToMint) = _getShareToMint(_nativeToken, _amount, moneyMarketDs);

    IWNative(_nativeToken).deposit{ value: _amount }();
    IbToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDepositETH(msg.sender, _nativeToken, _ibToken, _amount, _shareToMint);
  }

  function withdrawETH(address _ibWNativeToken, uint256 _shareAmount) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _token = moneyMarketDs.ibTokenToTokens[_ibWNativeToken];
    address _relayer = moneyMarketDs.nativeRelayer;
    if (_token != moneyMarketDs.nativeToken) revert LendFacet_InvalidToken(_token);
    if (_relayer == address(0)) revert LendFacet_InvalidAddress(_relayer);
    LibMoneyMarket01.accureInterest(_token, moneyMarketDs);

    uint256 _shareValue = _getShareValue(_token, _ibWNativeToken, _shareAmount, moneyMarketDs);

    IbToken(_ibWNativeToken).burn(msg.sender, _shareAmount);
    _safeUnwrap(_token, moneyMarketDs.nativeRelayer, msg.sender, _shareValue);

    emit LogWithdrawETH(msg.sender, _token, _ibWNativeToken, _shareAmount, _shareValue);
  }

  function getTotalToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);
  }

  function getTotalTokenWithPendingInterest(address _token) external view returns (uint256 _totalToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    // total token + pending interest that belong to lender
    _totalToken = LibMoneyMarket01.getTotalTokenWithPendingInterest(_token, moneyMarketDs);
  }

  // calculate _shareToMint to mint before transfer token to MM
  function _getShareToMint(
    address _token,
    uint256 _underlyingAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (address _ibToken, uint256 _shareToMint) {
    // calculate _shareToMint to mint before transfer token to MM
    uint256 _totalSupply;
    (_ibToken, _totalSupply, _shareToMint) = _getShareAmountFromValue(_token, _underlyingAmount, moneyMarketDs);

    uint256 _tokenDecimals = IbToken(_ibToken).decimals();

    if (_totalSupply + _shareToMint < 10**(_tokenDecimals) - 1) {
      revert LendFacet_NoTinyShares();
    }
  }

  function _getShareValue(
    address _token,
    address _ibToken,
    uint256 _shareAmount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal view returns (uint256 _shareValue) {
    uint256 _totalSupply = IbToken(_ibToken).totalSupply();
    uint256 _tokenDecimals = IbToken(_ibToken).decimals();
    uint256 _totalToken = LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);

    _shareValue = LibShareUtil.shareToValue(_shareAmount, _totalToken, _totalSupply);

    uint256 _shareLeft = _totalSupply - _shareAmount;
    if (_shareLeft != 0 && _shareLeft < 10**(_tokenDecimals) - 1) {
      revert LendFacet_NoTinyShares();
    }
  }

  function _getShareAmountFromValue(
    address _token,
    uint256 _value,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  )
    internal
    view
    returns (
      address _ibToken,
      uint256 _totalSupply,
      uint256 _ibShareAmount
    )
  {
    _ibToken = moneyMarketDs.tokenToIbTokens[_token];
    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_token);
    }

    _totalSupply = IbToken(_ibToken).totalSupply();
    uint256 _totalToken = LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);

    _ibShareAmount = LibShareUtil.valueToShare(_value, _totalSupply, _totalToken);
  }

  function getIbShareFromUnderlyingAmount(address _token, uint256 _underlyingAmount)
    external
    view
    returns (uint256 _ibShareAmount)
  {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    (, , _ibShareAmount) = _getShareAmountFromValue(_token, _underlyingAmount, moneyMarketDs);
  }

  function _safeUnwrap(
    address _nativeToken,
    address _nativeRelayer,
    address _to,
    uint256 _amount
  ) internal {
    LibSafeToken.safeTransfer(_nativeToken, _nativeRelayer, _amount);
    IWNativeRelayer(_nativeRelayer).withdraw(_amount);
    LibSafeToken.safeTransferETH(_to, _amount);
  }
}
