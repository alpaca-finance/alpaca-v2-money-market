// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
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
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { IInterestBearingToken } from "../interfaces/IInterestBearingToken.sol";

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

    _newIbToken = Clones.clone(moneyMarketDs.ibTokenImplementation);
    IInterestBearingToken(_newIbToken).initialize(_token, address(this));

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

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];
    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_token);
    }

    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    (, uint256 _shareToMint) = LibMoneyMarket01.getShareAmountFromValue(_token, _ibToken, _amount, moneyMarketDs);

    moneyMarketDs.reserves[_token] += _amount;
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IInterestBearingToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _shareToMint);
  }

  function withdraw(address _ibToken, uint256 _shareAmount) external nonReentrant returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    (address _token, uint256 _shareValue) = LibMoneyMarket01.withdraw(
      _ibToken,
      _shareAmount,
      msg.sender,
      moneyMarketDs
    );
    ERC20(_token).safeTransfer(msg.sender, _shareValue);
    return _shareValue;
  }

  function depositETH() external payable nonReentrant {
    if (msg.value == 0) revert LendFacet_InvalidAmount(msg.value);

    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    address _nativeToken = moneyMarketDs.nativeToken;
    if (_nativeToken == address(0)) revert LendFacet_InvalidToken(_nativeToken);

    address _ibToken = moneyMarketDs.tokenToIbTokens[_nativeToken];
    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_nativeToken);
    }

    LibMoneyMarket01.accrueInterest(_nativeToken, moneyMarketDs);

    (, uint256 _shareToMint) = LibMoneyMarket01.getShareAmountFromValue(
      _nativeToken,
      _ibToken,
      msg.value,
      moneyMarketDs
    );

    moneyMarketDs.reserves[_nativeToken] += msg.value;
    IWNative(_nativeToken).deposit{ value: msg.value }();
    IInterestBearingToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDepositETH(msg.sender, _nativeToken, _ibToken, msg.value, _shareToMint);
  }

  function withdrawETH(address _ibWNativeToken, uint256 _shareAmount) external nonReentrant {
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _token = moneyMarketDs.ibTokenToTokens[_ibWNativeToken];
    if (_token != moneyMarketDs.nativeToken) revert LendFacet_InvalidToken(_token);

    address _relayer = moneyMarketDs.nativeRelayer;
    if (_relayer == address(0)) revert LendFacet_InvalidAddress(_relayer);

    LibMoneyMarket01.accrueInterest(_token, moneyMarketDs);

    uint256 _shareValue = LibShareUtil.shareToValue(
      _shareAmount,
      LibMoneyMarket01.getTotalToken(_token, moneyMarketDs),
      IInterestBearingToken(_ibWNativeToken).totalSupply()
    );

    IInterestBearingToken(_ibWNativeToken).burn(msg.sender, _shareAmount);
    _safeUnwrap(_token, moneyMarketDs.nativeRelayer, msg.sender, _shareValue, moneyMarketDs);

    emit LogWithdrawETH(msg.sender, _token, _ibWNativeToken, _shareAmount, _shareValue);
  }

  function _safeUnwrap(
    address _nativeToken,
    address _nativeRelayer,
    address _to,
    uint256 _amount,
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs
  ) internal {
    if (_amount > moneyMarketDs.reserves[_nativeToken]) revert LibMoneyMarket01.LibMoneyMarket01_NotEnoughToken();
    moneyMarketDs.reserves[_nativeToken] -= _amount;
    LibSafeToken.safeTransfer(_nativeToken, _nativeRelayer, _amount);
    IWNativeRelayer(_nativeRelayer).withdraw(_amount);
    LibSafeToken.safeTransferETH(_to, _amount);
  }
}
