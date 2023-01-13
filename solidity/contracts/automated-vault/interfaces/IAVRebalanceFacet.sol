// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVRebalanceFacet {
  error AVRebalanceFacet_Unauthorized(address _caller);

  event LogRetarget(address indexed _vaultToken, uint256 _equityBefore, uint256 _equityAfter);

  function retarget(address _vaultToken) external;
}
