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
  /// @return _swapCalldata The modified swap calldata according to the input
  function getSwapCalldata(
    address _source,
    address _destination,
    uint256 _amountIn,
    address _to
  ) external view returns (bytes memory) {
    SwapInfo memory _swapInfo = swapInfos[_source][_destination];
    bytes memory _swapCalldata = _swapInfo.swapCalldata;
    _replace(_swapCalldata, _amountIn, _swapInfo.amountInOffset);
    _replace(_swapCalldata, _to, _swapInfo.toOffset);
    return _swapCalldata;
  }

  /// @notice Set swap info
  /// @param _source The source token
  /// @param _destination The destination token
  /// @param _swapInfo The swap info struct
  function setSwapInfo(
    address _source,
    address _destination,
    SwapInfo calldata _swapInfo
  ) external onlyOwner {
    uint256 _swapCalldataLength = _swapInfo.swapCalldata.length;
    uint256 _amountInOffset = _swapInfo.amountInOffset;
    uint256 _toOffset = _swapInfo.toOffset;

    // validate the offsets
    if (
      // check if the offset is more than function signature length
      (_amountInOffset < 4 || _toOffset < 4) ||
      // check if the offset is more than swap calldata length
      (_amountInOffset > _swapCalldataLength || _toOffset > _swapCalldataLength)
    ) {
      revert SwapHelper_InvalidAgrument();
    }

    swapInfos[_source][_destination] = _swapInfo;
  }

  function _replace(
    bytes memory _data,
    address _addr,
    uint256 _offset
  ) internal pure {
    assembly {
      // skip length to the data
      let dataPointer := add(_data, 32)
      // replace the data at the offset
      //  offset = length after the first data bytes + size of address
      mstore(add(_offset, dataPointer), _addr)
    }
  }

  function _replace(
    bytes memory _data,
    uint256 _amount,
    uint256 _offset
  ) internal pure {
    assembly {
      // skip length to the data
      let dataPointer := add(_data, 32)
      // replace the data at the offset
      //  offset = length after the first data bytes + size of uint256)
      mstore(add(_offset, dataPointer), _amount)
    }
  }
}
