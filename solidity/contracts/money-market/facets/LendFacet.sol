// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { ILendFacet } from "../interfaces/ILendFacet.sol";
import { IAdminFacet } from "../interfaces/IAdminFacet.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

import { IbToken } from "../IbToken.sol";

import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";

contract LendFacet is ILendFacet {
  using SafeERC20 for ERC20;

  event LogDeposit(
    address indexed _user,
    address _token,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  event LogWithdraw(
    address indexed _user,
    address _token,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  event LogOpenMarket(address indexed _user,
    address indexed _token,
    address _ibToken);

  // open isolate token market, able to borrow only
  function openMarket(address _token) external returns (address _newIbToken) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken != address(0)) {
      revert LendFacet_InvalidToken(_token);
    }

    string memory _tokenSymbol = IERC20(_token).symbol();
    uint8 _tokenDecimals = IERC20(_token).decimals();
    _newIbToken = address(
      new IbToken(
        string.concat("Interest Bearing ", _tokenSymbol),
        string.concat("IB", _tokenSymbol),
        _tokenDecimals
      )
    );

    LibMoneyMarket01.TokenConfig memory _tokenConfig = LibMoneyMarket01
      .TokenConfig({
        tier: LibMoneyMarket01.AssetTier.ISOLATE,
        collateralFactor: 0,
        // todo: tbd
        borrowingFactor: 8500,
        maxCollateral: 0,
        // todo: tbd
        maxBorrow: 100e18,
        maxToleranceExpiredSecond: 86400
      });

    LibMoneyMarket01.setIbPair(_token, _newIbToken, moneyMarketDs);
    LibMoneyMarket01.setTokenConfig(_token, _tokenConfig, moneyMarketDs);

    emit LogOpenMarket(msg.sender, _token, _newIbToken);
  }

  function deposit(address _token, uint256 _amount) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    LibMoneyMarket01.accureInterest(_token, moneyMarketDs);
    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken == address(0)) {
      revert LendFacet_InvalidToken(_token);
    }
    uint256 _totalSupply = IbToken(_ibToken).totalSupply();
    uint256 _tokenDecimals = IbToken(_ibToken).decimals();
    uint256 _totalToken = LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);

    // calculate _shareToMint to mint before transfer token to MM
    uint256 _shareToMint = LibShareUtil.valueToShare(
      _totalSupply,
      _amount,
      _totalToken
    );

    if (_totalSupply + _shareToMint < 10**(_tokenDecimals) - 1) {
      revert LendFacet_NoTinyShares();
    }

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IbToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _shareToMint);
  }

  function withdraw(address _ibToken, uint256 _shareAmount) external {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _token = moneyMarketDs.ibTokenToTokens[_ibToken];

    LibMoneyMarket01.accureInterest(_token, moneyMarketDs);

    if (_token == address(0)) {
      revert LendFacet_InvalidToken(_ibToken);
    }

    uint256 _totalSupply = IbToken(_ibToken).totalSupply();
    uint256 _tokenDecimals = IbToken(_ibToken).decimals();
    uint256 _totalToken = LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);

    uint256 _shareValue = LibShareUtil.shareToValue(
      _shareAmount,
      _totalToken,
      _totalSupply
    );

    uint256 _shareLeft = _totalSupply - _shareAmount;
    if (_shareLeft != 0 && _shareLeft < 10**(_tokenDecimals) - 1) {
      revert LendFacet_NoTinyShares();
    }

    IbToken(_ibToken).burn(msg.sender, _shareAmount);
    ERC20(_token).safeTransfer(msg.sender, _shareValue);

    emit LogWithdraw(msg.sender, _token, _ibToken, _shareAmount, _shareValue);
  }

  function getTotalToken(address _token) external view returns (uint256) {
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    return LibMoneyMarket01.getTotalToken(_token, moneyMarketDs);
  }

}
