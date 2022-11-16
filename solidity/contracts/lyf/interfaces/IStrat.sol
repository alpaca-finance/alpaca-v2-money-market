// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStrat {
  function composeLPToken(
    address _token0,
    address _token1,
    address _lpToken,
    uint256 _token0Amount,
    uint256 _token1Amount,
    uint256 _minLPAmount
  ) external;
}
