// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// interfaces
import { IAVPancakeSwapHandler } from "../interfaces/IAVPancakeSwapHandler.sol";
import { IPancakeRouter02 } from "../interfaces/IPancakeRouter02.sol";
import { IPancakePair } from "../interfaces/IPancakePair.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

// libraries
import { LibFullMath } from "../libraries/LibFullMath.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

contract AVPancakeSwapHandler is IAVPancakeSwapHandler, Initializable, OwnableUpgradeable {
  using LibSafeToken for IERC20;

  mapping(address => bool) public whitelistedCallers;

  IPancakeRouter02 public router;
  IPancakePair public lpToken;

  uint256 public totalLpBalance;

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert AVPancakeSwapHandler_Unauthorized(msg.sender);
    }
    _;
  }

  function initialize(address _router, address _lpToken) public initializer {
    OwnableUpgradeable.__Ownable_init();
    router = IPancakeRouter02(_router);
    lpToken = IPancakePair(_lpToken);
  }

  function onDeposit(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLpAmount
  ) external onlyWhitelisted returns (uint256 _mintedLpAmount) {
    _mintedLpAmount = composeLpToken(_token0, _token1, _token0Amount, _token1Amount, _minLpAmount);
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
  }

  function composeLpToken(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLpAmount
  ) internal returns (uint256 _mintedLpAmount) {
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

    uint256 _token0Before = IERC20(_token0).balanceOf(address(this));
    uint256 _token1Before = IERC20(_token1).balanceOf(address(this));

    router.removeLiquidity(_token0, _token1, _lpToRemove, 0, 0, address(this), block.timestamp);

    _returnedToken0 = IERC20(_token0).balanceOf(address(this)) - _token0Before;
    _returnedToken1 = IERC20(_token1).balanceOf(address(this)) - _token1Before;
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
}
