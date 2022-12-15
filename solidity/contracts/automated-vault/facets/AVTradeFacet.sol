// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IAVTradeFacet } from "../interfaces/IAVTradeFacet.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";
import { IMoneyMarket } from "../interfaces/IMoneyMarket.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

contract AVTradeFacet is IAVTradeFacet {
  using SafeERC20 for ERC20;

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
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    LibAV01.VaultConfig memory vaultConfig = avDs.vaultConfigs[_shareToken];
    address _stableToken = vaultConfig.stableToken;
    address _assetToken = vaultConfig.assetToken;

    LibAV01.deposit(_shareToken, _stableToken, _stableAmountIn, _minShareOut);

    (uint256 _stableBorrowAmount, uint256 _assetBorrowAmount) = LibAV01.calcBorrowAmount(
      _stableToken,
      _assetToken,
      _stableAmountIn,
      vaultConfig.leverageLevel,
      avDs
    );

    _borrowFromMoneyMarket(_shareToken, _stableToken, _stableBorrowAmount, avDs);
    _borrowFromMoneyMarket(_shareToken, _assetToken, _assetBorrowAmount, avDs);

    // TODO: send tokens to handler to compose LP and farm

    emit LogDeposit(msg.sender, _shareToken, _stableToken, _stableAmountIn);
  }

  function withdraw(
    address _shareToken,
    uint256 _shareAmountIn,
    uint256 _minTokenOut
  ) external nonReentrant {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    LibAV01.withdraw(_shareToken, _shareAmountIn, _minTokenOut, avDs);
  }

  function _borrowFromMoneyMarket(
    address _shareToken,
    address _token,
    uint256 _amountToBorrow,
    LibAV01.AVDiamondStorage storage avDs
  ) internal {
    IMoneyMarket(avDs.moneyMarket).nonCollatBorrow(_token, _amountToBorrow);

    avDs.vaultDebtShares[_shareToken] += LibShareUtil.valueToShareRoundingUp(
      _amountToBorrow,
      avDs.vaultDebtShares[_shareToken],
      avDs.vaultDebtValues[_shareToken]
    );
    avDs.vaultDebtValues[_shareToken] += _amountToBorrow;
  }

  /// @notice only do accounting of av debt but doesn't actually repay to money market
  function _removeDebt(
    address _shareToken,
    uint256 _amountToRemove,
    LibAV01.AVDiamondStorage storage avDs
  ) internal {
    uint256 _shareToRemove = LibShareUtil.valueToShare(
      _amountToRemove,
      avDs.vaultDebtShares[_shareToken],
      avDs.vaultDebtValues[_shareToken]
    );
    avDs.vaultDebtShares[_shareToken] -= _shareToRemove;
    avDs.vaultDebtValues[_shareToken] -= _amountToRemove;

    emit LogRemoveDebt(_shareToken, _shareToRemove, _amountToRemove);
  }
}
