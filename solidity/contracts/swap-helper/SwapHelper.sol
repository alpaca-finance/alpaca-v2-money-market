// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISwapHelper } from "../interfaces/ISwapHelper.sol";

contract SwapHelper is ISwapHelper, Ownable {
  // source => desination => SwapInfo
  mapping(address => mapping(address => SwapInfo)) public swapInfos;

  /// @notice Get swap calldata
  /// @param _source The source token
  /// @param _destination The destination token
  /// @param _amountIn The amount in
  /// @param _to The destination address
  /// @return the router address
  /// @return the modified swap calldata according to the input
  function getSwapCalldata(
    address _source,
    address _destination,
    uint256 _amountIn,
    address _to,
    uint256 _minAmountOut
  ) external view override returns (address, bytes memory) {
    SwapInfo memory _swapInfo = swapInfos[_source][_destination];
    if (_swapInfo.router == address(0)) {
      revert SwapHelper_SwapInfoNotFound(_source, _destination);
    }
    bytes memory _swapCalldata = _swapInfo.swapCalldata;
    _replace(_swapCalldata, _amountIn, _swapInfo.amountInOffset);
    _replace(_swapCalldata, _to, _swapInfo.toOffset);
    _replace(_swapCalldata, _minAmountOut, _swapInfo.minAmountOutOffset);
    return (_swapInfo.router, _swapCalldata);
  }

  /// @notice Set multiple swap infos
  /// @param _pathInputs The path inputs that contains source, destination, and swap info
  function setSwapInfos(PathInput[] calldata _pathInputs) external override onlyOwner {
    uint256 _pathInputsLength = _pathInputs.length;
    for (uint256 _i; _i < _pathInputsLength; ) {
      _setSwapInfo(_pathInputs[_i].source, _pathInputs[_i].destination, _pathInputs[_i].info);
      unchecked {
        ++_i;
      }
    }
  }

  /// @dev Set swap info with validated offset
  /// @param _source The source token
  /// @param _destination The destination token
  /// @param _swapInfo The swap info struct
  function _setSwapInfo(address _source, address _destination, SwapInfo calldata _swapInfo) internal {
    uint256 _swapCalldataLength = _swapInfo.swapCalldata.length;
    uint256 _amountInOffset = _swapInfo.amountInOffset;
    uint256 _toOffset = _swapInfo.toOffset;
    uint256 _minAmountOutOffset = _swapInfo.minAmountOutOffset;

    // validate the offsets
    if (
      // check if the offsets are the same
      (_amountInOffset == _toOffset) ||
      (_toOffset == _minAmountOutOffset) ||
      (_amountInOffset == _minAmountOutOffset) ||
      // check if the offset is more than function signature length
      (_amountInOffset < 4 || _toOffset < 4 || _minAmountOutOffset < 4) ||
      // check if the offset with data size is more than swap calldata length
      //  reserve 32 bytes for replaced data size
      (_toOffset > _swapCalldataLength - 32 ||
        _amountInOffset > _swapCalldataLength - 32 ||
        _minAmountOutOffset > _swapCalldataLength - 32)
    ) {
      revert SwapHelper_InvalidAgrument();
    }

    swapInfos[_source][_destination] = _swapInfo;
  }

  function _replace(bytes memory _data, address _addr, uint256 _offset) internal pure {
    assembly {
      // skip length to the data
      let dataPointer := add(_data, 32)
      // replace the data at the offset
      //  offset = length after the first data byte + 32 (padding 0 + address size)
      mstore(add(_offset, dataPointer), _addr)
    }
  }

  function _replace(bytes memory _data, uint256 _amount, uint256 _offset) internal pure {
    assembly {
      // skip length to the data
      let dataPointer := add(_data, 32)
      // replace the data at the offset
      //  offset = length after the first data byte + 32
      mstore(add(_offset, dataPointer), _amount)
    }
  }

  /// @notice helper function for `setSwapInfo`
  /// @dev beware of using this function, it's not ensured that the offset is correct in all cases
  /// @param _calldata The calldata
  /// @param _query The query
  /// @return _offset the offset of the query
  function search(bytes memory _calldata, address _query) external pure returns (uint256 _offset) {
    // search for address(0x0) might result in invalid offset
    if (_query == address(0x0)) {
      revert SwapHelper_InvalidAgrument();
    }
    assembly {
      // skip length to the data
      let dataPointer := add(_calldata, 32)
      // get the length of the calldata
      let dataLength := mload(_calldata)
      // loop through the calldata
      for {
        let i := 0
      } lt(i, dataLength) {
        i := add(i, 1)
      } {
        // get the current data pointer
        let currentPointer := add(dataPointer, i)
        // check if the current data is the query
        if eq(mload(currentPointer), _query) {
          // return the offset
          _offset := i
          // break the loop
          i := dataLength
        }
      }
    }
  }

  function search(bytes memory _calldata, uint256 _query) external pure returns (uint256 _offset) {
    // search for 0 might result in invalid offset
    if (_query == 0) {
      revert SwapHelper_InvalidAgrument();
    }
    assembly {
      // skip length to the data
      let dataPointer := add(_calldata, 32)
      // get the length of the calldata
      let dataLength := mload(_calldata)
      // loop through the calldata
      for {
        let i := 0
      } lt(i, dataLength) {
        i := add(i, 1)
      } {
        // get the current data pointer
        let currentPointer := add(dataPointer, i)
        // check if the current data is the query
        if eq(mload(currentPointer), _query) {
          // return the offset
          _offset := i
          // break the loop
          i := dataLength
        }
      }
    }
  }
}
