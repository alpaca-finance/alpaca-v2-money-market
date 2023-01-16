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

    if (!avDs.operatorsOk[msg.sender]) {
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
      uint256 _stableBorrowValueUSD = uint256(_deltaDebt / 2);
      uint256 _stableBorrowAmount = LibAV01.getTokenAmountFromUSDValue(
        _vaultConfig.stableToken,
        _stableBorrowValueUSD,
        avDs
      );
      uint256 _assetBorrowAmount = LibAV01.getTokenAmountFromUSDValue(
        _vaultConfig.stableToken,
        uint256(_deltaDebt) - _stableBorrowValueUSD, // prevent precision loss from _deltaDebt / 2
        avDs
      );

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

  function repurchase(
    address _vaultToken,
    address _tokenToRepay,
    uint256 _amountToRepay
  ) external {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    if (!avDs.repurchasersOk[msg.sender]) {
      revert AVRebalanceFacet_Unauthorized(msg.sender);
    }

    LibAV01.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];
    address _tokenToBorrow;
    if (_tokenToRepay == _vaultConfig.stableToken) {
      _tokenToBorrow = _vaultConfig.assetToken;
    } else if (_tokenToRepay == _vaultConfig.assetToken) {
      _tokenToBorrow = _vaultConfig.stableToken;
    } else {
      revert AVRebalanceFacet_InvalidToken(_tokenToRepay);
    }

    LibAV01.accrueVaultInterest(_vaultToken, avDs);
    LibAV01.mintManagementFeeToTreasury(_vaultToken, avDs);

    // repay
    IERC20(_tokenToRepay).safeTransferFrom(msg.sender, address(this), _amountToRepay);
    LibAV01.repayVaultDebt(_vaultToken, _tokenToRepay, _amountToRepay, avDs);

    // borrow value equal to _amountToRepay in USD + reward
    uint256 _amountToBorrowForVault = LibAV01.getTokenAmountFromUSDValue(
      _tokenToBorrow,
      LibAV01.getTokenInUSD(_tokenToRepay, _amountToRepay, avDs),
      avDs
    );
    uint256 _repurchaseRewardAmount = (_amountToBorrowForVault * avDs.repurchaseRewardBps) / LibAV01.MAX_BPS;
    uint256 _amountToRepurchaser = _amountToBorrowForVault + _repurchaseRewardAmount;
    LibAV01.borrowMoneyMarket(_vaultToken, _tokenToBorrow, _amountToRepurchaser, avDs);

    // transfer reward to caller
    IERC20(_tokenToBorrow).safeTransfer(msg.sender, _amountToRepurchaser);

    emit LogRepurchase(_vaultToken, _tokenToRepay, _amountToRepay, _amountToBorrowForVault, _repurchaseRewardAmount);
  }
}
