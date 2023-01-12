// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { IAVRebalanceFacet } from "../interfaces/IAVRebalanceFacet.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

contract AVRebalanceFacet is IAVRebalanceFacet {
  using LibSafeToken for IERC20;

  function retarget(address _vaultToken) external {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    if (!avDs.rebalancerOk[msg.sender]) {
      revert AVRebalanceFacet_Unauthorized(msg.sender);
    }

    LibAV01.accrueVaultInterest(_vaultToken, avDs);
    LibAV01.mintManagementFeeToTreasury(_vaultToken, avDs);

    LibAV01.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];

    uint256 _currentEquity = LibAV01.getEquity(_vaultToken, _vaultConfig.handler, avDs);
    // deltaDebt = targetDebt - currentDebt ; targetDebt = currentEquity * (leverage - 1)
    // this line would not overflow int256 since we periodically do retargeting
    // so real debt should not diverge from target that much and cause overflow
    int256 _deltaDebt = int256(_currentEquity * (_vaultConfig.leverageLevel - 1)) -
      int256(LibAV01.getVaultTotalDebtInUSD(_vaultToken, _vaultConfig.lpToken, avDs));

    if (_deltaDebt > 0) {
      // _deltaDebt > 0 means that the vault has less debt than targeted debt value
      // so we need to borrow more to increase debt to match targeted value
      // borrow both for _deltaDebt / 2 and deposit to handler
      uint256 _borrowValueUSD = uint256(_deltaDebt / 2);
      uint256 _stableBorrowAmount = LibAV01.getTokenAmountFromUSDValue(_vaultConfig.stableToken, _borrowValueUSD, avDs);
      uint256 _assetBorrowAmount = LibAV01.getTokenAmountFromUSDValue(_vaultConfig.stableToken, _borrowValueUSD, avDs);

      LibAV01.borrowMoneyMarket(_vaultToken, _vaultConfig.stableToken, _stableBorrowAmount, avDs);
      LibAV01.borrowMoneyMarket(_vaultToken, _vaultConfig.assetToken, _assetBorrowAmount, avDs);

      LibAV01.depositToHandler(
        _vaultConfig.handler,
        _vaultToken,
        _vaultConfig.stableToken,
        _vaultConfig.assetToken,
        _stableBorrowAmount,
        _assetBorrowAmount,
        _currentEquity,
        avDs
      );
    } else if (_deltaDebt < 0) {
      // _deltaDebt < 0 means that the vault has more debt that targeted debt value
      // so we need to repay to lessen current debt to match targeted value
      // withdraw lp value equal to deltaDebt and repay
      (uint256 _withdrawalStableAmount, uint256 _withdrawalAssetAmount) = LibAV01.withdrawFromHandler(
        _vaultToken,
        _vaultConfig.handler,
        LibAV01.getTokenAmountFromUSDValue(_vaultConfig.lpToken, uint256(-_deltaDebt), avDs),
        avDs
      );

      // TODO: handle case where withdraw and repay more than debt

      LibAV01.repayVaultDebt(_vaultToken, _vaultConfig.stableToken, _withdrawalStableAmount, avDs);
      LibAV01.repayVaultDebt(_vaultToken, _vaultConfig.assetToken, _withdrawalAssetAmount, avDs);
    }

    emit LogRetarget(_vaultToken, _currentEquity, LibAV01.getEquity(_vaultToken, _vaultConfig.handler, avDs));
  }
}
