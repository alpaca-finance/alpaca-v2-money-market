// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// interfaces
import { IAVTradeFacet } from "../interfaces/IAVTradeFacet.sol";
import { IAVVaultToken } from "../interfaces/IAVVaultToken.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IAVHandler } from "../interfaces/IAVHandler.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibAVConstant } from "../libraries/LibAVConstant.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

contract AVTradeFacet is IAVTradeFacet {
  using LibSafeToken for IERC20;

  event LogRemoveDebt(address indexed vaultToken, uint256 debtShareRemoved, uint256 debtValueRemoved);
  event LogDeposit(
    address indexed user,
    address indexed vaultToken,
    address stableToken,
    uint256 stableAmountDeposited
  );
  // todo: add fields
  event LogWithdraw(
    address indexed user,
    address indexed vaultToken,
    uint256 burnedAmount,
    address stableToken,
    uint256 stableAmountToUser,
    uint256 assetAmountToUser
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function deposit(
    address _vaultToken,
    uint256 _stableAmountIn,
    uint256 _minShareOut
  ) external nonReentrant {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();

    LibAV01.accrueVaultInterest(_vaultToken, avDs);

    LibAV01.mintManagementFeeToTreasury(_vaultToken, avDs);

    LibAVConstant.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];
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

    uint256 _equityBefore = LibAV01.getEquity(_vaultToken, _vaultConfig.handler, avDs);

    // borrow from MM
    LibAV01.borrowMoneyMarket(_vaultToken, _stableToken, _stableBorrowAmount, avDs);
    LibAV01.borrowMoneyMarket(_vaultToken, _assetToken, _assetBorrowAmount, avDs);

    uint256 _shareToMint = LibAV01.depositToHandler(
      _vaultConfig.handler,
      _vaultToken,
      _stableToken,
      _assetToken,
      _stableAmountIn + _stableBorrowAmount,
      _assetBorrowAmount,
      _equityBefore,
      avDs
    );

    if (_minShareOut > _shareToMint) revert AVTradeFacet_TooLittleReceived();

    IAVVaultToken(_vaultToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _vaultToken, _stableToken, _stableAmountIn);
  }

  // TODO: discuss code ordering
  struct WithdrawLocalVars {
    uint256 withdrawalStableAmount;
    uint256 withdrawalAssetAmount;
    uint256 totalShareSupply;
  }

  function withdraw(
    address _vaultToken,
    uint256 _shareToWithdraw,
    uint256 _minStableTokenOut,
    uint256 _minAssetTokenOut
  ) external nonReentrant {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.avDiamondStorage();
    LibAVConstant.VaultConfig memory _vaultConfig = avDs.vaultConfigs[_vaultToken];
    WithdrawLocalVars memory vars;

    // 0. accrue interest, mint management fee
    LibAV01.accrueVaultInterest(_vaultToken, avDs);
    LibAV01.mintManagementFeeToTreasury(_vaultToken, avDs);

    // 1. withdraw from handler
    vars.totalShareSupply = IAVVaultToken(_vaultToken).totalSupply();
    (vars.withdrawalStableAmount, vars.withdrawalAssetAmount) = LibAV01.withdrawFromHandler(
      _vaultToken,
      _vaultConfig.handler,
      (IAVHandler(_vaultConfig.handler).totalLpBalance() * _shareToWithdraw) / vars.totalShareSupply,
      avDs
    );

    // 2. repay vault debt
    uint256 _stableTokenToUser = _repay(
      _vaultToken,
      _vaultConfig.stableToken,
      (avDs.vaultDebts[_vaultToken][_vaultConfig.stableToken] * _shareToWithdraw) / vars.totalShareSupply,
      vars.withdrawalStableAmount,
      _minStableTokenOut,
      avDs
    );
    uint256 _assetTokenToUser = _repay(
      _vaultToken,
      _vaultConfig.assetToken,
      (avDs.vaultDebts[_vaultToken][_vaultConfig.assetToken] * _shareToWithdraw) / vars.totalShareSupply,
      vars.withdrawalAssetAmount,
      _minAssetTokenOut,
      avDs
    );

    // 3. transfer tokens
    IAVVaultToken(_vaultToken).burn(msg.sender, _shareToWithdraw);
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

  function _repay(
    address _vaultToken,
    address _token,
    uint256 _repayAmount,
    uint256 _tokenAvailable,
    uint256 _minTokenOut,
    LibAV01.AVDiamondStorage storage avDs
  ) internal returns (uint256 _tokenToUser) {
    if (_tokenAvailable < _repayAmount) {
      // TODO: handle case where tokens returned from lp not enough to cover debt
      // should swap other token to missing token
      _tokenToUser = 0;
    } else {
      _tokenToUser = _tokenAvailable - _repayAmount;
    }

    if (_tokenToUser < _minTokenOut) {
      revert AVTradeFacet_TooLittleReceived();
    }

    LibAV01.repayVaultDebt(_vaultToken, _token, _repayAmount, avDs);
  }
}
