// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../utils/Components.sol";

import { DSTest } from "solidity/tests/base/DSTest.sol";
import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";

contract SwapHelper_BaseFork is DSTest {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  IERC20 public constant btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IERC20 public constant eth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IERC20 public constant doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);

  address internal constant RECIPIENT = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal constant RECIPIENT_2 = 0x09FC1B9B288647FF0b5b4668C74e51F8bEA50C67;
  address internal constant BINANCE_HOT_WALLET = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

  IPancakeSwapRouterV3 public pancakeV3Router = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);

  ISwapHelper public swapHelper;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 29_033_259);
    swapHelper = new SwapHelper();
  }
}

contract SwapHelper_GetSwapCalldata is SwapHelper_BaseFork {
  function testCorrectness_GetSwapCalldata_SwapOnPancakeShouldWork() public {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 2500;

    uint256 _amountIn = 100e18;
    address _to = RECIPIENT;

    // prepare origin swap calldata
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, _poolFee, _token1),
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: 0
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    // set swap info
    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: address(pancakeV3Router),
      amountInOffset: 128 + 4,
      toOffset: 64 + 4
    });

    swapHelper.setSwapInfo(_token0, _token1, _swapInfo);

    // get swap calldata with modified amountIn and to

    uint256 _newAmountIn = 200e18;
    address _newTo = RECIPIENT_2;
    (, bytes memory _replacedCalldata) = swapHelper.getSwapCalldata(_token0, _token1, _newAmountIn, _newTo);

    // ====== do swap with pancake swap ======

    // swap to original recipient with original amountIn

    bytes memory _returnData;
    uint256 _wbnbBalanceBefore = wbnb.balanceOf(_to);

    vm.startPrank(BINANCE_HOT_WALLET);

    usdt.approve(address(pancakeV3Router), _amountIn);
    (, _returnData) = address(pancakeV3Router).call(_calldata);
    uint256 _amountOut = abi.decode(_returnData, (uint256));

    vm.stopPrank();

    assertEq(wbnb.balanceOf(RECIPIENT), _wbnbBalanceBefore + _amountOut);

    // swap to new recipient with new amountIn

    _wbnbBalanceBefore = wbnb.balanceOf(_newTo);

    vm.startPrank(BINANCE_HOT_WALLET);

    usdt.approve(address(pancakeV3Router), _newAmountIn);
    (, _returnData) = address(pancakeV3Router).call(_replacedCalldata);
    uint256 _newAmountOut = abi.decode(_returnData, (uint256));

    vm.stopPrank();

    assertEq(wbnb.balanceOf(_newTo), _wbnbBalanceBefore + _newAmountOut);

    // since newAmountIn is greater than original amountIn
    assertGt(_newAmountOut, _amountOut);
  }
}

contract SwapHelper_SetSwapInfo is SwapHelper_BaseFork {
  function testCorrectness_SetSwapInfo_ShouldWork() public {
    address _token0 = address(usdc);
    address _token1 = address(cake);
    uint24 _poolFee = 3000;

    uint256 _amountIn = 10e18;
    address _to = RECIPIENT;

    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, _poolFee, _token1),
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: 0
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    swapHelper.setSwapInfo(
      _token0,
      _token1,
      ISwapHelper.SwapInfo({
        swapCalldata: _calldata,
        router: address(pancakeV3Router),
        amountInOffset: 128 + 4,
        toOffset: 64 + 4
      })
    );

    // get swap calldata with same amountIn and to should be the same
    (address _router, bytes memory _retrievedCalldata) = swapHelper.getSwapCalldata(_token0, _token1, _amountIn, _to);
    assertEq(_router, address(pancakeV3Router));
    assertEq(keccak256(_retrievedCalldata), keccak256(_calldata));
  }

  function testRevert_SetSwapInfo_InvalidOffset() public {
    // test revert when offset is less than function signature length
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({ swapCalldata: "", router: address(pancakeV3Router), amountInOffset: 0, toOffset: 0 })
    );

    // test revert when offset is more than swap calldata length
    bytes memory _mockCalldata = abi.encode(address(usdc), address(cake), address(pancakeV3Router));
    uint256 _mockCalldataLength = _mockCalldata.length;

    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({
        swapCalldata: _mockCalldata,
        router: address(pancakeV3Router),
        amountInOffset: _mockCalldataLength + 1,
        toOffset: _mockCalldataLength + 1
      })
    );
  }

  function testRevert_SetSwapInfo_WhenCallerIsNotOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(RECIPIENT);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({ swapCalldata: "", router: address(pancakeV3Router), amountInOffset: 0, toOffset: 0 })
    );
  }
}
