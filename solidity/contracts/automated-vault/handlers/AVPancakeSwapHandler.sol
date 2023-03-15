// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// interfaces
import { IAutomatedVault } from "../interfaces/IAutomatedVault.sol";
import { IAVPancakeSwapHandler } from "../interfaces/IAVPancakeSwapHandler.sol";
import { IPancakeRouter02 } from "../interfaces/IPancakeRouter02.sol";
import { IPancakePair } from "../interfaces/IPancakePair.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";

// libraries
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

contract AVPancakeSwapHandler is IAVPancakeSwapHandler, Initializable, OwnableUpgradeable {
  using LibSafeToken for IERC20;

  mapping(address => bool) public whitelistedCallers;

  IPancakeRouter02 public router;
  IPancakePair public lpToken;

  uint256 public totalLpBalance;

  IAutomatedVault public av;

  IAlpacaV2Oracle public oracle;

  address public stableToken;
  address public assetToken;

  uint8 public leverageLevel;

  uint256 public stableTokenTo18ConversionFactor;
  uint256 public assetTokenTo18ConversionFactor;

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert AVPancakeSwapHandler_Unauthorized(msg.sender);
    }
    _;
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _router,
    address _lpToken,
    address _av,
    address _oracle,
    address _stableToken,
    address _assetToken,
    uint8 _leverageLevel
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    // todo: sanity check
    router = IPancakeRouter02(_router);
    lpToken = IPancakePair(_lpToken);
    av = IAutomatedVault(_av);
    oracle = IAlpacaV2Oracle(_oracle);

    stableToken = _stableToken;
    assetToken = _assetToken;
    leverageLevel = _leverageLevel;

    stableTokenTo18ConversionFactor = to18ConversionFactor(_stableToken);
    assetTokenTo18ConversionFactor = to18ConversionFactor(_assetToken);
  }

  function onDeposit(
    address _stableToken,
    address _assetToken,
    uint256 _stableAmount,
    uint256 _assetAmount,
    uint256 _minLpAmount
  ) external onlyWhitelisted returns (uint256 _mintedLpAmount) {
    _mintedLpAmount = composeLpToken(_stableToken, _assetToken, _stableAmount, _assetAmount, _minLpAmount);
    totalLpBalance += _mintedLpAmount;
  }

  function onWithdraw(uint256 _lpAmountToWithdraw)
    external
    onlyWhitelisted
    returns (uint256 _returnedToken0, uint256 _returnedToken1)
  {
    address _token0 = lpToken.token0();
    address _token1 = lpToken.token1();

    (_returnedToken0, _returnedToken1) = removeLiquidity(_lpAmountToWithdraw, _token0, _token1);

    IERC20(_token0).safeTransfer(msg.sender, _returnedToken0);
    IERC20(_token1).safeTransfer(msg.sender, _returnedToken1);

    totalLpBalance -= _lpAmountToWithdraw;

    emit LogOnWithdraw(address(lpToken), _lpAmountToWithdraw);
  }

  function composeLpToken(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLpAmount
  ) internal returns (uint256 _mintedLpAmount) {
    // 0. Sort token
    // todo: this can be set during initialize to save gas
    if (_token0 != lpToken.token0()) {
      (_token0, _token1) = (_token1, _token0);
      (_token0Amount, _token1Amount) = (_token1Amount, _token0Amount);
    }
    // 1. Approve router to do their stuffs
    IERC20(_token0).safeApprove(address(router), type(uint256).max);
    IERC20(_token1).safeApprove(address(router), type(uint256).max);

    // 2. Compute the optimal amount of BaseToken and FarmingToken to be converted.
    uint256 swapAmt;
    bool isReversed;
    {
      (uint256 r0, uint256 r1, ) = lpToken.getReserves();
      (swapAmt, isReversed) = optimalDeposit(_token0Amount, _token1Amount, r0, r1);
    }
    // 3. Convert between BaseToken and farming tokens
    address[] memory path = new address[](2);
    (path[0], path[1]) = isReversed ? (_token1, _token0) : (_token0, _token1);
    // 4. Swap according to path
    if (swapAmt > 0) router.swapExactTokensForTokens(swapAmt, 0, path, address(this), block.timestamp);
    // 5. Mint more LP tokens and return all LP tokens to the sender.
    (, , _mintedLpAmount) = router.addLiquidity(
      _token0,
      _token1,
      IERC20(_token0).balanceOf(address(this)),
      IERC20(_token1).balanceOf(address(this)),
      0,
      0,
      address(this),
      block.timestamp
    );
    if (_mintedLpAmount < _minLpAmount) {
      revert AVPancakeSwapHandler_TooLittleReceived();
    }

    // 7. Reset approve to 0 for safety reason
    IERC20(_token0).safeApprove(address(router), 0);
    IERC20(_token1).safeApprove(address(router), 0);
  }

  function removeLiquidity(
    uint256 _lpToRemove,
    address _token0,
    address _token1
  ) internal returns (uint256 _returnedToken0, uint256 _returnedToken1) {
    IERC20(address(lpToken)).safeIncreaseAllowance(address(router), _lpToRemove);

    (_returnedToken0, _returnedToken1) = router.removeLiquidity(
      _token0,
      _token1,
      _lpToRemove,
      0, // min token0 amount
      0, // min token1 amount
      address(this),
      block.timestamp
    );
  }

  /// @dev Compute optimal deposit amount
  /// @param amtA amount of token A desired to deposit
  /// @param amtB amonut of token B desired to deposit
  /// @param resA amount of token A in reserve
  /// @param resB amount of token B in reserve
  function optimalDeposit(
    uint256 amtA,
    uint256 amtB,
    uint256 resA,
    uint256 resB
  ) internal pure returns (uint256 swapAmt, bool isReversed) {
    if (amtA * resB >= amtB * resA) {
      swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
      isReversed = false;
    } else {
      swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
      isReversed = true;
    }
  }

  /// @dev Compute optimal deposit amount helper
  /// @param amtA amount of token A desired to deposit
  /// @param amtB amonut of token B desired to deposit
  /// @param resA amount of token A in reserve
  /// @param resB amount of token B in reserve
  function _optimalDepositA(
    uint256 amtA,
    uint256 amtB,
    uint256 resA,
    uint256 resB
  ) internal pure returns (uint256) {
    if (amtA * (resB) < amtB * (resA)) {
      revert AVPancakeSwapHandler_Reverse();
    }

    uint256 a = 9975;
    uint256 b = uint256(19975) * (resA);
    uint256 _c = (amtA * (resB)) - (amtB * (resA));
    uint256 c = ((_c * (10000)) / (amtB + (resB))) * (resA);

    uint256 d = a * (c) * (4);
    uint256 e = LibFullMath.sqrt(b * (b) + (d));

    uint256 numerator = e - (b);
    uint256 denominator = a * (2);

    return numerator / (denominator);
  }

  function setWhitelistedCallers(address[] calldata _callers, bool _isOk) external onlyOwner {
    uint256 _len = _callers.length;
    for (uint256 _i = 0; _i < _len; ) {
      whitelistedCallers[_callers[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }

  function to18ConversionFactor(address _token) internal view returns (uint64) {
    uint256 _decimals = IERC20(_token).decimals();
    if (_decimals > 18) revert AVPancakeSwapHandler_UnsuppportedDecimals();
    uint256 _conversionFactor = 10**(18 - _decimals);
    return uint64(_conversionFactor);
  }

  // todo: move this to executor
  function calculateBorrowAmount(uint256 _stableDepositedAmount)
    external
    view
    returns (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount)
  {
    (uint256 _stablePrice, ) = oracle.getTokenPrice(stableToken);
    (uint256 _assetPrice, ) = oracle.getTokenPrice(assetToken);

    uint256 _stableDepositedValue = (_stableDepositedAmount * stableTokenTo18ConversionFactor * _stablePrice) / 1e18;
    uint256 _targetBorrowValue = _stableDepositedValue * leverageLevel;

    uint256 _stableBorrowValue = _targetBorrowValue / 2;
    uint256 _assetBorrowValue = _targetBorrowValue - _stableBorrowValue;

    _stableBorrowAmount =
      ((_stableBorrowValue - _stableDepositedValue) * 1e18) /
      (_stablePrice * stableTokenTo18ConversionFactor);
    _assetBorrowAmount = (_assetBorrowValue * 1e18) / (_assetPrice * assetTokenTo18ConversionFactor);
  }

  function getAUMinUSD() external view returns (uint256 _value) {
    (_value, ) = oracle.lpToDollar(totalLpBalance, address(lpToken));
  }
}
