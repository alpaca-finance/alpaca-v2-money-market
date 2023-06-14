// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../utils/Components.sol";

import { DSTest } from "solidity/tests/base/DSTest.sol";
import { SwapHelper } from "solidity/contracts/swap-helper/SwapHelper.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { ISwapHelper } from "solidity/contracts/interfaces/ISwapHelper.sol";
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

  address internal constant USD = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  address internal constant RECIPIENT = 0x2DD872C6f7275DAD633d7Deb1083EDA561E9B96b;
  address internal constant RECIPIENT_2 = 0x09FC1B9B288647FF0b5b4668C74e51F8bEA50C67;

  IOracleMedianizer public oracleMedianizer = IOracleMedianizer(0x553b8adc2Ac16491Ec57239BeA7191719a2B880c);
  IPancakeSwapRouterV3 public pancakeV3Router = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);

  ISwapHelper public swapHelper;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 29_033_259);
    swapHelper = new SwapHelper();

    deal(address(usdt), address(this), 300e18);
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

contract SwapHelper_GetSwapCalldata is SwapHelper_BaseFork {
  function testCorrectness_GetSwapCalldata_SwapOnPancakeShouldWork() public {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 2500;

    uint256 _amountIn = 100e18;
    address _to = RECIPIENT;
    uint256 _minAmountOut = _getMinAmountOut(_token0, _token1, _amountIn, 500);

    // prepare origin swap calldata
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, _poolFee, _token1),
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    // set swap info
    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: address(pancakeV3Router),
      amountInOffset: 128 + 4,
      toOffset: 64 + 4,
      minAmountOutOffset: 160 + 4
    });

    swapHelper.setSwapInfo(_token0, _token1, _swapInfo);

    // get swap calldata with modified amountIn and to

    uint256 _newAmountIn = 200e18;
    address _newTo = RECIPIENT_2;
    uint256 _newMinAmountOut = _getMinAmountOut(_token0, _token1, _newAmountIn, 500);
    (address _router, bytes memory _replacedCalldata) = swapHelper.getSwapCalldata(
      _token0,
      _token1,
      _newAmountIn,
      _newTo,
      _newMinAmountOut
    );

    // ====== do swap with pancake swap ======

    // swap to original recipient with original amountIn

    bytes memory _returnData;
    uint256 _wbnbBalanceBefore = wbnb.balanceOf(_to);

    usdt.approve(address(pancakeV3Router), _amountIn);
    (, _returnData) = address(pancakeV3Router).call(_calldata);
    uint256 _amountOut = abi.decode(_returnData, (uint256));

    assertEq(wbnb.balanceOf(_to), _wbnbBalanceBefore + _amountOut);

    // swap to new recipient with new amountIn

    _wbnbBalanceBefore = wbnb.balanceOf(_newTo);

    usdt.approve(_router, _newAmountIn);
    (, _returnData) = _router.call(_replacedCalldata);
    uint256 _newAmountOut = abi.decode(_returnData, (uint256));

    assertEq(wbnb.balanceOf(_newTo), _wbnbBalanceBefore + _newAmountOut);

    // since newAmountIn is greater than original amountIn
    assertGt(_newAmountOut, _amountOut);
    assertGt(_newMinAmountOut, _minAmountOut);
  }

  function testCorrectness_GetSwapCalldata_WithZeroMinAmountOut() public {
    // TODO: test set minAmountOut = 0
    address _token0 = address(eth);
    address _token1 = address(usdc);
    uint24 _poolFee = 3000;

    uint256 _amountIn = 1e18;
    address _to = RECIPIENT;
    uint256 _minAmountOut = _getMinAmountOut(_token0, _token1, _amountIn, 500);

    // prepare origin swap calldata
    bytes memory _calldata = abi.encodeCall(
      IPancakeSwapRouterV3.exactInput,
      IPancakeSwapRouterV3.ExactInputParams({
        path: abi.encodePacked(_token0, _poolFee, _token1),
        recipient: _to,
        deadline: type(uint256).max,
        amountIn: _amountIn,
        amountOutMinimum: _minAmountOut
      })
    );

    // build same calldata with minAmountOut = 0
    bytes memory _zeroMinAmountOutcalldata = abi.encodeCall(
      IPancakeSwapRouterV3.exactInput,
      IPancakeSwapRouterV3.ExactInputParams({
        path: abi.encodePacked(_token0, _poolFee, _token1),
        recipient: _to,
        deadline: type(uint256).max,
        amountIn: _amountIn,
        amountOutMinimum: 0
      })
    );

    // set swap info
    swapHelper.setSwapInfo(
      _token0,
      _token1,
      ISwapHelper.SwapInfo({
        swapCalldata: _calldata,
        router: address(pancakeV3Router),
        amountInOffset: 128 + 4,
        toOffset: 64 + 4,
        minAmountOutOffset: 160 + 4
      })
    );

    // get swap calldata with minAmountOut = 0 from SwapHelper
    (, bytes memory _replacedCalldata) = swapHelper.getSwapCalldata(_token0, _token1, _amountIn, _to, 0);

    // modified calldata from SwapHelper should be the same as the one with minAmountOut = 0
    assertEq(keccak256(_replacedCalldata), keccak256(_zeroMinAmountOutcalldata));
  }
}

contract SwapHelper_SetSwapInfo is SwapHelper_BaseFork {
  function testCorrectness_SetSwapInfo_ShouldWork() public {
    address _token0 = address(usdc);
    address _token1 = address(cake);
    uint24 _poolFee = 3000;

    uint256 _amountIn = 10e18;
    address _to = RECIPIENT;
    uint256 _minAmountOut = 0;

    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, _poolFee, _token1),
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    swapHelper.setSwapInfo(
      _token0,
      _token1,
      ISwapHelper.SwapInfo({
        swapCalldata: _calldata,
        router: address(pancakeV3Router),
        amountInOffset: 128 + 4,
        toOffset: 64 + 4,
        minAmountOutOffset: 160 + 4
      })
    );

    // get swap calldata with same amountIn and to should be the same
    (address _router, bytes memory _retrievedCalldata) = swapHelper.getSwapCalldata(
      _token0,
      _token1,
      _amountIn,
      _to,
      _minAmountOut
    );
    assertEq(_router, address(pancakeV3Router));
    assertEq(keccak256(_retrievedCalldata), keccak256(_calldata));
  }

  function testRevert_SetSwapInfo_InvalidOffset() public {
    // test revert when offset is more than swap calldata length
    bytes memory _mockCalldata = abi.encodeWithSignature("mockCall(address,address)", address(usdc), address(cake));
    // _mockCalldata length = 4 + 32 + 32 = 68 Bytes

    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    // offset is included function signature length
    //  and there is only one data to be replaced, so offset should not be more than 4 bytes
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({
        swapCalldata: _mockCalldata,
        router: address(pancakeV3Router),
        amountInOffset: 5 + 32, // should revert with this offset
        toOffset: 4,
        minAmountOutOffset: 5
      })
    );

    // test revert when offsets are the same
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({
        swapCalldata: _mockCalldata,
        router: address(pancakeV3Router),
        amountInOffset: 4,
        toOffset: 4,
        minAmountOutOffset: 4
      })
    );

    // test revert when offset is less than function signature length
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({
        swapCalldata: _mockCalldata,
        router: address(pancakeV3Router),
        amountInOffset: 0,
        toOffset: 1,
        minAmountOutOffset: 2
      })
    );
  }

  function testRevert_SetSwapInfo_WhenCallerIsNotOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(RECIPIENT);
    swapHelper.setSwapInfo(
      address(usdc),
      address(cake),
      ISwapHelper.SwapInfo({
        swapCalldata: "",
        router: address(pancakeV3Router),
        amountInOffset: 0,
        toOffset: 0,
        minAmountOutOffset: 0
      })
    );
  }
}

contract SwapHelper_Search is SwapHelper_BaseFork {
  function testRevert_Search_ByZeroAddress() public {
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.search("", address(0x0));
  }

  function testRevert_Search_ByZeroAmount() public {
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    swapHelper.search("", 0);
  }

  function testCorrectness_Search_ShouldReturnCorrectOffset() public {
    bytes memory _mockCalldata = abi.encodeWithSignature(
      "mockCall(address, address, uint256)",
      address(usdc),
      address(cake),
      100e18
    );
    // _mockCalldata length = 4 + 32 + 32 + 32 = 100 Bytes
    //
    //  structure: function signature + 3 * 32 bytes data
    //    offset of usdc = 4 bytes
    //    offset of cake = 4 + 32 = 36 bytes
    //    offset of 100e18 = 4 + 32 + 32 = 68 bytes

    assertEq(swapHelper.search(_mockCalldata, address(usdc)), 4);
    assertEq(swapHelper.search(_mockCalldata, address(cake)), 36);
    assertEq(swapHelper.search(_mockCalldata, 100e18), 68);
  }

  function testCorrectness_Search_ShouldWorkOnRealData() public {
    // test with pancake swap calldata
    //  same as `testCorrectness_GetSwapCalldata_SwapOnPancakeShouldWork()`
    //  but using search function to get offset
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 2500;

    uint256 _amountIn = 100e18;
    address _to = RECIPIENT;
    uint256 _minAmountOut = _getMinAmountOut(_token0, _token1, _amountIn, 500);

    // prepare origin swap calldata
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, _poolFee, _token1),
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut
    });

    bytes memory _calldata = abi.encodeCall(IPancakeSwapRouterV3.exactInput, _params);

    // set swap info
    ISwapHelper.SwapInfo memory _swapInfo = ISwapHelper.SwapInfo({
      swapCalldata: _calldata,
      router: address(pancakeV3Router),
      amountInOffset: swapHelper.search(_calldata, _amountIn),
      toOffset: swapHelper.search(_calldata, _to),
      minAmountOutOffset: swapHelper.search(_calldata, _minAmountOut)
    });

    swapHelper.setSwapInfo(_token0, _token1, _swapInfo);

    // get swap calldata with modified amountIn and to

    uint256 _newAmountIn = 200e18;
    address _newTo = RECIPIENT_2;
    uint256 _newMinAmountOut = _getMinAmountOut(_token0, _token1, _newAmountIn, 500);
    (address _router, bytes memory _replacedCalldata) = swapHelper.getSwapCalldata(
      _token0,
      _token1,
      _newAmountIn,
      _newTo,
      _newMinAmountOut
    );

    // ====== do swap with pancake swap ======

    // swap to original recipient with original amountIn

    bytes memory _returnData;
    uint256 _wbnbBalanceBefore = wbnb.balanceOf(_to);

    usdt.approve(address(pancakeV3Router), _amountIn);
    (, _returnData) = address(pancakeV3Router).call(_calldata);
    uint256 _amountOut = abi.decode(_returnData, (uint256));

    assertEq(wbnb.balanceOf(_to), _wbnbBalanceBefore + _amountOut);

    // swap to new recipient with new amountIn

    _wbnbBalanceBefore = wbnb.balanceOf(_newTo);

    usdt.approve(_router, _newAmountIn);
    (, _returnData) = _router.call(_replacedCalldata);
    uint256 _newAmountOut = abi.decode(_returnData, (uint256));

    assertEq(wbnb.balanceOf(_newTo), _wbnbBalanceBefore + _newAmountOut);

    // since newAmountIn is greater than original amountIn
    assertGt(_newAmountOut, _amountOut);
    assertGt(_newMinAmountOut, _minAmountOut);
  }
}