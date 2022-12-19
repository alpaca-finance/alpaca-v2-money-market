// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IAVPancakeSwapHandler } from "../interfaces/IAVPancakeSwapHandler.sol";
import { IPancakeRouter02 } from "../interfaces/IPancakeRouter02.sol";
import { IPancakePair } from "../interfaces/IPancakePair.sol";

// libraries
import { LibFullMath } from "../libraries/LibFullMath.sol";

contract AVPancakeSwapHandler is IAVPancakeSwapHandler, Initializable {
  using SafeERC20 for ERC20;

  IPancakeRouter02 public router;
  IPancakePair public lpToken;

  uint256 public totalLpBalance;

  function initialize(address _router, address _lpToken) public initializer {
    router = IPancakeRouter02(_router);
    lpToken = IPancakePair(_lpToken);
  }

  function onDeposit(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLPAmount
  ) external returns (uint256 _mintedLiquidity) {
    _mintedLiquidity = composeLiquidity(_token0, _token1, _token0Amount, _token1Amount, _minLPAmount);
    totalLpBalance += _mintedLiquidity;
  }

  function composeLiquidity(
    address _token0,
    address _token1,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLiquidityToMint
  ) internal returns (uint256 _mintedLiquidity) {
    // 1. Approve router to do their stuffs
    ERC20(_token0).safeApprove(address(router), type(uint256).max);
    ERC20(_token1).safeApprove(address(router), type(uint256).max);

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
    (, , _mintedLiquidity) = router.addLiquidity(
      _token0,
      _token1,
      ERC20(_token0).balanceOf(address(this)),
      ERC20(_token1).balanceOf(address(this)),
      0,
      0,
      address(this),
      block.timestamp
    );
    if (_mintedLiquidity < _minLiquidityToMint) {
      revert AVPancakeSwapHandler_TooLittleReceived();
    }

    // 7. Reset approve to 0 for safety reason
    ERC20(_token0).safeApprove(address(router), 0);
    ERC20(_token1).safeApprove(address(router), 0);
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
}
