// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SwapHelper_BaseFork.t.sol";

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
