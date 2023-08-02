// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../utils/Components.sol";

import { DSTest } from "solidity/tests/base/DSTest.sol";
import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IThenaRouterV2 } from "solidity/contracts/interfaces/IThenaRouterV2.sol";
import { IThenaRouterV3 } from "solidity/contracts/interfaces/IThenaRouterV3.sol";
import { IOracleMedianizer } from "solidity/contracts/oracle/interfaces/IOracleMedianizer.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";

contract SwapHelper_BaseFork is DSTest, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  IERC20 public constant btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IERC20 public constant eth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IERC20 public constant doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);
  IERC20 public constant the = IERC20(0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11);
  IERC20 public constant busd = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

  address internal constant USD = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  address internal constant RECIPIENT = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal constant RECIPIENT_2 = 0x09FC1B9B288647FF0b5b4668C74e51F8bEA50C67;

  IThenaRouterV2 public thenaRouterV2 = IThenaRouterV2(0xd4ae6eCA985340Dd434D38F470aCCce4DC78D109);
  IThenaRouterV3 public thenaRouterV3 = IThenaRouterV3(0x327Dd3208f0bCF590A66110aCB6e5e6941A4EfA0);
  IOracleMedianizer public oracleMedianizer = IOracleMedianizer(0x553b8adc2Ac16491Ec57239BeA7191719a2B880c);
  IPancakeSwapRouterV3 public pancakeV3Router = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);

  ISwapHelper public swapHelper;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 29_033_259);
    swapHelper = new SwapHelper();

    deal(address(usdt), address(this), 300e18);
  }

  // try to solve stack too deep error
  function _setSingleSwapInfo(
    address _token0,
    address _token1,
    ISwapHelper.SwapInfo memory _swapInfo
  ) internal {
    ISwapHelper.PathInput[] memory _pathInputs = new ISwapHelper.PathInput[](1);
    _pathInputs[0] = ISwapHelper.PathInput({ source: _token0, destination: _token1, info: _swapInfo });

    swapHelper.setSwapInfos(_pathInputs);
  }

  function _getMinAmountOut(
    address _token0,
    address _token1,
    uint256 _amountIn,
    uint256 slippageToleranceBps
  ) internal view returns (uint256 _minAmountOut) {
    (uint256 _token0Price, ) = oracleMedianizer.getPrice(_token0, USD);

    uint256 _minAmountOutUSD = (_amountIn * _token0Price * (LibConstant.MAX_BPS - slippageToleranceBps)) /
      (10**IERC20(_token0).decimals() * LibConstant.MAX_BPS);

    (uint256 _token1Price, ) = oracleMedianizer.getPrice(_token1, USD);
    _minAmountOut = ((_minAmountOutUSD * (10**IERC20(_token1).decimals())) / _token1Price);
  }
}
