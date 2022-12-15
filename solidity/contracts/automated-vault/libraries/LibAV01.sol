// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { ISwapPairLike } from "../interfaces/ISwapPairLike.sol";

library LibAV01 {
  using SafeERC20 for ERC20;

  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  struct ShareTokenConfig {
    uint256 someConfig; // TODO: replace with real config
  }

  struct Position {
    address owner;
    uint256 debtShare;
  }

  struct AVDiamondStorage {
    address moneyMarket;
    address oracle;
    mapping(address => address) tokenToShareToken;
    mapping(address => address) shareTokenToToken;
    mapping(address => ShareTokenConfig) shareTokenConfig;
    // todo: multiple handler
    address avHandler;
    // share token => handler
    mapping(address => address) avHandlers;
    // share token => debt token => debt share
    mapping(address => mapping(address => uint256)) totalDebtShares;
    mapping(address => mapping(address => uint256)) totalDebtValues;
  }

  error LibAV01_InvalidToken(address _token);
  error LibAV01_NoTinyShares();
  error LibAV01_TooLittleReceived();
  error LibAV01_InvalidHandler();
  error LibAV01_UnTrustedPrice();

  function getStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }

  function deposit(
    address _token0,
    address _token1,
    uint256 _amountIn,
    uint256 _minShareOut,
    AVDiamondStorage storage avDs
  ) internal {
    address _shareToken = avDs.tokenToShareToken[_token0];
    address _handler = avDs.avHandlers[_shareToken];

    if (_shareToken == address(0)) revert LibAV01_InvalidToken(_token0);
    if (_handler == address(0)) revert LibAV01_InvalidHandler();

    // todo: calculate borrowed amount
    uint256 _borrowedAmount0 = _amountIn;
    uint256 _borrowedAmount1 = _amountIn * 2;

    _borrowMoneyMarket(_shareToken, _token0, _borrowedAmount0, avDs);
    _borrowMoneyMarket(_shareToken, _token1, _borrowedAmount1, avDs);

    uint256 _desiredAmount0 = _amountIn + _borrowedAmount0;
    uint256 _desiredAmount1 = _borrowedAmount1;

    // todo: refactor?
    ERC20(_token0).safeTransferFrom(msg.sender, address(this), _amountIn);
    ERC20(_token0).safeTransfer(_handler, _desiredAmount0);
    ERC20(_token1).safeTransfer(_handler, _desiredAmount1);

    uint256 _equityBefore = _getEquity(_shareToken, _handler, avDs);

    IAVHandler(_handler).onDeposit(
      _token0,
      _token1,
      _desiredAmount0,
      _desiredAmount1,
      0 // min lp amount
    );

    // _equityAfter should be latest equity
    uint256 _equityAfter = _getEquity(_shareToken, _handler, avDs);
    // equity after should more than before
    uint256 _equityChanged = _equityAfter - _equityBefore;

    uint256 _totalShareTokenSupply = ERC20(_shareToken).totalSupply();

    uint256 _shareToMint = LibShareUtil.valueToShare(_equityChanged, _totalShareTokenSupply, _equityAfter);

    if (_minShareOut > _shareToMint) revert LibAV01_TooLittleReceived();

    if (_totalShareTokenSupply + _shareToMint < 10**(ERC20(_shareToken).decimals()) - 1) revert LibAV01_NoTinyShares();

    IAVShareToken(_shareToken).mint(msg.sender, _shareToMint);
  }

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut,
    AVDiamondStorage storage avDs
  ) internal {
    address _token = avDs.shareTokenToToken[_shareToken];
    if (_token == address(0)) {
      revert LibAV01_InvalidToken(_shareToken);
    }

    // TODO: calculate amountOut with equity value
    // TODO: handle slippage

    IAVShareToken(_shareToken).burn(msg.sender, _shareAmountIn);
    ERC20(_token).safeTransferFrom(msg.sender, address(this), _minTokenOut);
  }

  function setShareTokenPair(
    address _token,
    address _shareToken,
    AVDiamondStorage storage avDs
  ) internal {
    avDs.tokenToShareToken[_token] = _shareToken;
    avDs.shareTokenToToken[_shareToken] = _token;
  }

  function _getEquity(
    address _shareToken,
    address _handler,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256 _equity) {
    ISwapPairLike _lpToken = IAVHandler(_handler).lpToken();
    address _token0 = _lpToken.token0();
    address _token1 = _lpToken.token1();
    uint256 _lpAmount = IAVHandler(_handler).totalLpBalance();
    // get price USD
    uint256 _totalDebtValue = avDs.totalDebtValues[_shareToken][_token0] + avDs.totalDebtValues[_shareToken][_token1];
    _equity = _lpToValue(_lpAmount, address(_lpToken), avDs) - _totalDebtValue;
  }

  function _borrowMoneyMarket(
    address _shareToken,
    address _token,
    uint256 _amount,
    AVDiamondStorage storage avDs
  ) internal {
    uint256 _totalSupply = ERC20(_shareToken).totalSupply();
    uint256 _totalValue = avDs.totalDebtValues[_shareToken][_token];

    IMoneyMarket(avDs.moneyMarket).nonCollatBorrow(_token, _amount);

    uint256 _shareToAdd = LibShareUtil.valueToShareRoundingUp(_amount, _totalSupply, _totalValue);

    // update debt
    avDs.totalDebtShares[_shareToken][_token] += _shareToAdd;
    avDs.totalDebtValues[_shareToken][_token] += _amount;
  }

  /// @notice Return value of given lp amount.
  /// @param _lpAmount Amount of lp.
  function _lpToValue(
    uint256 _lpAmount,
    address _lpToken,
    AVDiamondStorage storage avDs
  ) internal view returns (uint256) {
    (uint256 _lpValue, uint256 _lastUpdated) = IAlpacaV2Oracle(avDs.oracle).lpToDollar(_lpAmount, _lpToken);
    if (block.timestamp - _lastUpdated > 86400) revert LibAV01_UnTrustedPrice();
    return _lpValue;
  }
}
