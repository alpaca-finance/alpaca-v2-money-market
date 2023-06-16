// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SwapHelper_BaseFork.t.sol";

contract SwapHelper_SetSwapInfos is SwapHelper_BaseFork {
  function testCorrectness_SetSwapInfos_ShouldWork() public {
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

  function testRevert_SetSwapInfos_InvalidOffset() public {
    // test revert when offset is more than swap calldata length
    bytes memory _mockCalldata = abi.encodeWithSignature("mockCall(address,address)", address(usdc), address(cake));
    // _mockCalldata length = 4 + 32 + 32 = 68 Bytes

    // test revert when offset is greater than calldata length
    vm.expectRevert(ISwapHelper.SwapHelper_InvalidAgrument.selector);
    // offset is included function signature length
    //  and there is two data to be replaced, so offset should not be more than 4 + 32 bytes
    _setSingleSwapInfo(
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
    _setSingleSwapInfo(
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
    _setSingleSwapInfo(
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

  function testRevert_SetSwapInfos_WhenCallerIsNotOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(RECIPIENT);
    swapHelper.setSwapInfos(new ISwapHelper.PathInput[](1));
  }
}
