// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDoublyLinkedList } from "../libraries/LibDoublyLinkedList.sol";
import { LibReentrancyGuard } from "../libraries/LibReentrancyGuard.sol";

// interfaces
import { ILYFCollateralFacet } from "../interfaces/ILYFCollateralFacet.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IMasterChefLike } from "../interfaces/IMasterChefLike.sol";

contract LYFCollateralFacet is ILYFCollateralFacet {
  using LibSafeToken for IERC20;
  using LibDoublyLinkedList for LibDoublyLinkedList.List;

  event LogAddCollateral(
    address indexed _account,
    uint256 indexed _subAccountId,
    address indexed _token,
    address _caller,
    uint256 _amount
  );
  event LogRemoveCollateral(
    address indexed _account,
    uint256 indexed _subAccountId,
    address indexed _token,
    uint256 _amount
  );

  event LogTransferCollateral(
    address indexed _account,
    uint256 indexed _fromSubAccountId,
    uint256 indexed _toSubAccountId,
    address _token,
    uint256 _amount
  );

  modifier nonReentrant() {
    LibReentrancyGuard.lock();
    _;
    LibReentrancyGuard.unlock();
  }

  function addCollateral(
    address _account,
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    if (lyfDs.tokenConfigs[_token].tier != LibLYF01.AssetTier.COLLATERAL) {
      revert LYFCollateralFacet_OnlyCollateralTierAllowed();
    }
    if (_amount + lyfDs.collats[_token] > lyfDs.tokenConfigs[_token].maxCollateral) {
      revert LYFCollateralFacet_ExceedCollateralLimit();
    }

    address _subAccount = LibLYF01.getSubAccount(_account, _subAccountId);

    // revert if amount received != expected amount (_amount)
    LibLYF01.pullExactTokens(_token, msg.sender, _amount);

    LibLYF01.addCollat(_subAccount, _token, _amount, lyfDs);

    emit LogAddCollateral(_account, _subAccountId, _token, msg.sender, _amount);
  }

  function removeCollateral(
    uint256 _subAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // allow token to be removed if the tier's changed
    if (lyfDs.tokenConfigs[_token].tier == LibLYF01.AssetTier.LP) {
      revert LYFCollateralFacet_RemoveLPCollateralNotAllowed();
    }

    address _subAccount = LibLYF01.getSubAccount(msg.sender, _subAccountId);

    LibLYF01.accrueDebtSharesOf(_subAccount, lyfDs);

    uint256 _actualAmountRemoved = LibLYF01.removeCollateral(_subAccount, _token, _amount, lyfDs);

    // violate check-effect pattern for gas optimization, will change after come up with a way that doesn't loop
    if (!LibLYF01.isSubaccountHealthy(_subAccount, lyfDs)) {
      revert LYFCollateralFacet_BorrowingPowerTooLow();
    }

    IERC20(_token).safeTransfer(msg.sender, _actualAmountRemoved);

    emit LogRemoveCollateral(msg.sender, _subAccountId, _token, _actualAmountRemoved);
  }

  function transferCollateral(
    uint256 _fromSubAccountId,
    uint256 _toSubAccountId,
    address _token,
    uint256 _amount
  ) external nonReentrant {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    if (lyfDs.tokenConfigs[_token].tier != LibLYF01.AssetTier.COLLATERAL) {
      revert LYFCollateralFacet_OnlyCollateralTierAllowed();
    }

    address _fromSubAccount = LibLYF01.getSubAccount(msg.sender, _fromSubAccountId);

    LibLYF01.accrueDebtSharesOf(_fromSubAccount, lyfDs);

    uint256 _actualAmountRemoved = LibLYF01.removeCollateral(_fromSubAccount, _token, _amount, lyfDs);

    if (!LibLYF01.isSubaccountHealthy(_fromSubAccount, lyfDs)) {
      revert LYFCollateralFacet_BorrowingPowerTooLow();
    }

    address _toSubAccount = LibLYF01.getSubAccount(msg.sender, _toSubAccountId);

    LibLYF01.addCollat(_toSubAccount, _token, _actualAmountRemoved, lyfDs);

    emit LogTransferCollateral(msg.sender, _fromSubAccountId, _toSubAccountId, _token, _actualAmountRemoved);
  }
}
