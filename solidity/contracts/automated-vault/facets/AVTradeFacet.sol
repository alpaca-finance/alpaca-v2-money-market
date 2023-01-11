// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// interfaces
import { IAVTradeFacet } from "../interfaces/IAVTradeFacet.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

contract AVTradeFacet is IAVTradeFacet {
  using LibSafeToken for IERC20;

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function deposit(
    address _shareToken,
    uint256 _stableAmountIn,
    uint256 _minShareOut
  ) external nonReentrant {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    LibAV01.accrueVaultInterest(_shareToken, avDs);

    _mintManagementFeeToTreasury(_shareToken, avDs);

    LibAV01.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_shareToken];
    address _stableToken = _vaultConfig.stableToken;
    address _assetToken = _vaultConfig.assetToken;

    (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount) = LibAV01.calculateBorrowAmount(
      _stableToken,
      _assetToken,
      _stableAmountIn,
      _vaultConfig.leverageLevel,
      avDs
    );

    // get fund from user
    IERC20(_stableToken).safeTransferFrom(msg.sender, address(this), _stableAmountIn);

    uint256 _equityBefore = LibAV01.getEquity(_shareToken, _vaultConfig.handler, avDs);

    // borrow from MM
    LibAV01.borrowMoneyMarket(_shareToken, _stableToken, _stableBorrowAmount, avDs);
    LibAV01.borrowMoneyMarket(_shareToken, _assetToken, _assetBorrowAmount, avDs);

    uint256 _shareToMint = LibAV01.depositToHandler(
      _vaultConfig.handler,
      _shareToken,
      _stableToken,
      _assetToken,
      _stableAmountIn + _stableBorrowAmount,
      _assetBorrowAmount,
      _equityBefore,
      avDs
    );

    if (_minShareOut > _shareToMint) revert AVTradeFacet_TooLittleReceived();

    IAVShareToken(_shareToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _shareToken, _stableToken, _stableAmountIn);
  }

  function withdraw(
    address _vaultToken,
    uint256 _shareToWithdraw,
    uint256 _minStableTokenOut,
    uint256 _minAssetTokenOut
  ) external nonReentrant {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    LibAV01.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];

    // 0. accrue interest, mint management fee
    LibAV01.accrueVaultInterest(_vaultToken, avDs);
    _mintManagementFeeToTreasury(_vaultToken, avDs);

    // 1. withdraw from handler
    (uint256 _withdrawalStableAmount, uint256 _withdrawalAssetAmount) = LibAV01.withdrawFromHandler(
      _vaultToken,
      _shareToWithdraw,
      avDs
    );

    // TODO: handle case where tokens returned from lp not enough to cover debt

    // 2. check slippage, repay vault debt
    uint256 _totalShareSupply = IAVShareToken(_vaultToken).totalSupply();
    uint256 _stableRepayAmount = (avDs.vaultDebts[_vaultToken][_vaultConfig.stableToken] * _shareToWithdraw) /
      _totalShareSupply;
    uint256 _assetRepayAmount = (avDs.vaultDebts[_vaultToken][_vaultConfig.assetToken] * _shareToWithdraw) /
      _totalShareSupply;

    uint256 _stableTokenToUser = _withdrawalStableAmount - _stableRepayAmount;
    uint256 _assetTokenToUser = _withdrawalAssetAmount - _assetRepayAmount;
    if (_stableTokenToUser < _minStableTokenOut) {
      revert AVTradeFacet_TooLittleReceived();
    }
    if (_assetTokenToUser < _minAssetTokenOut) {
      revert AVTradeFacet_TooLittleReceived();
    }

    LibAV01.repayVaultDebt(_vaultToken, _vaultConfig.stableToken, _stableRepayAmount, avDs);
    LibAV01.repayVaultDebt(_vaultToken, _vaultConfig.assetToken, _assetRepayAmount, avDs);

    // 3. transfer tokens
    IAVShareToken(_vaultToken).burn(msg.sender, _shareToWithdraw);
    IERC20(_vaultConfig.stableToken).safeTransfer(msg.sender, _stableTokenToUser);
    IERC20(_vaultConfig.assetToken).safeTransfer(msg.sender, _assetTokenToUser);

    emit LogWithdraw(
      msg.sender,
      _vaultToken,
      _shareToWithdraw,
      _vaultConfig.stableToken,
      _stableTokenToUser,
      _assetTokenToUser
    );
  }

  function _mintManagementFeeToTreasury(address _shareToken, LibAV01.AVDiamondStorage storage avDs) internal {
    IAVShareToken(_shareToken).mint(avDs.treasury, LibAV01.getPendingManagementFee(_shareToken, avDs));

    avDs.lastFeeCollectionTimestamps[_shareToken] = block.timestamp;
  }
}
