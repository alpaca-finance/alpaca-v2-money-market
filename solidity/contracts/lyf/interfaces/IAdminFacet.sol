// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAdminFacet {
  function setOracle(address _oracle) external;

  function oracle() external view returns (address);
}
