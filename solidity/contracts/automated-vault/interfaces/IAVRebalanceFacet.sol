// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IAVRebalanceFacet {
  error AVRebalanceFacet_Unauthorized(address _caller);
  error AVRebalanceFacet_InvalidToken(address _token);

  function retarget(address _vaultToken) external;

  function repurchase(
    address _vaultToken,
    address _tokenToRepay,
    uint256 _amountToRepay
  ) external;
}
