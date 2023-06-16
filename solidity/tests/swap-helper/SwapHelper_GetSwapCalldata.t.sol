// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SwapHelper_BaseFork.t.sol";

contract SwapHelper_GetSwapCalldata is SwapHelper_BaseFork {
  function testCorrectness_GetSwapCalldata_SwapOnPancakeShouldWork() public {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);

    uint256 _amountIn = 100e18;
    address _to = RECIPIENT;
    uint256 _minAmountOut = _getMinAmountOut(_token0, _token1, _amountIn, 500);

    // prepare origin swap calldata
    IPancakeSwapRouterV3.ExactInputParams memory _params = IPancakeSwapRouterV3.ExactInputParams({
      path: abi.encodePacked(_token0, uint24(2500), _token1),
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

    _setSingleSwapInfo(_token0, _token1, _swapInfo);

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
    _setSingleSwapInfo(
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

  function testCorrectness_GetSwapCalldata_ThenaFusionSwap() public {
    // test thena fusion swap in script format
    //  to verify the correctness of config script and thena's swap router
    address _token0 = address(wbnb);
    address _token1 = address(the);

    address _to = address(RECIPIENT);
    uint256 _amountIn = type(uint256).max / 5; // 0x333...
    uint256 _minAmountOut = type(uint256).max / 3; // 0x555...

    IThenaRouterV3.ExactInputSingleParams memory _params = IThenaRouterV3.ExactInputSingleParams({
      tokenIn: _token0,
      tokenOut: _token1,
      recipient: _to,
      deadline: type(uint256).max,
      amountIn: _amountIn,
      amountOutMinimum: _minAmountOut,
      limitSqrtPrice: 0
    });

    bytes memory _calldata = abi.encodeCall(IThenaRouterV3.exactInputSingle, (_params));

    uint256 _amountInOffset = swapHelper.search(_calldata, _amountIn);
    uint256 _toOffset = swapHelper.search(_calldata, _to);
    uint256 _minAmountOutOffset = swapHelper.search(_calldata, _minAmountOut);

    // cross check
    assertEq(_amountInOffset, 132);
    assertEq(_toOffset, 68);
    assertEq(_minAmountOutOffset, 164);

    _setSingleSwapInfo(
      _token0,
      _token1,
      ISwapHelper.SwapInfo({
        swapCalldata: _calldata,
        router: address(thenaRouterV3),
        amountInOffset: _amountInOffset,
        toOffset: _toOffset,
        minAmountOutOffset: _minAmountOutOffset
      })
    );

    uint256 _newMinAmountOut = _getMinAmountOut(address(wbnb), address(the), 10e18, 500);

    (address _router, bytes memory _retrievedCalldata) = swapHelper.getSwapCalldata(
      _token0,
      _token1,
      10e18,
      _to,
      _newMinAmountOut
    );

    uint256 _balanceBefore = the.balanceOf(RECIPIENT);

    deal(address(wbnb), address(this), 10e18);
    wbnb.approve(_router, 10e18);
    (, bytes memory _returnData) = _router.call(_retrievedCalldata);

    uint256 _amountOut = abi.decode(_returnData, (uint256));

    assertEq(the.balanceOf(RECIPIENT), _balanceBefore + _amountOut);
  }

  function testRevert_GetSwapCalldata_SwapInfoNotFound() public {
    vm.expectRevert(abi.encodeWithSelector(ISwapHelper.SwapHelper_SwapInfoNotFound.selector, address(1), address(2)));
    swapHelper.getSwapCalldata(address(1), address(2), 0, address(this), 0);
  }
}
