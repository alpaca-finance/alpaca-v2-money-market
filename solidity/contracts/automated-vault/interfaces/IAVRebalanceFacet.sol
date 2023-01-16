// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

interface IAVRebalanceFacet {
  error AVRebalanceFacet_Unauthorized(address _caller);
  error AVRebalanceFacet_InvalidToken(address _token);

  event LogRetarget(address indexed _vaultToken, uint256 _equityBefore, uint256 _equityAfter);
  event LogRepurchase(
    address indexed _vaultToken,
    address _tokenToRepay,
    uint256 _amountRepaid,
    uint256 _amountBorrowedForVault,
    uint256 _repurchaseReward
  );

  function retarget(address _vaultToken) external;

  function repurchase(
    address _vaultToken,
    address _tokenToRepay,
    uint256 _amountToRepay
  ) external;
}
