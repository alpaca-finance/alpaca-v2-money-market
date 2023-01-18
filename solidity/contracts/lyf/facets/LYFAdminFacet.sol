// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- Libraries ---- //
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";
import { LibSafeToken } from "../libraries/LibSafeToken.sol";

// ---- Interfaces ---- //
import { ILYFAdminFacet } from "../interfaces/ILYFAdminFacet.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

contract LYFAdminFacet is ILYFAdminFacet {
  using LibSafeToken for IERC20;

  event LogSetMaxNumOfToken(uint256 _maxNumOfCollat);
  event LogSetMinDebtSize(uint256 _newValue);
  event LogWitdrawReserve(address indexed _token, address indexed _to, uint256 _amount);

  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function setOracle(address _oracle) external onlyOwner {
    IAlpacaV2Oracle(_oracle).dollarToLp(0, address(0));
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = _oracle;
  }

  function setTokenConfigs(TokenConfigInput[] calldata _tokenConfigs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _inputLength = _tokenConfigs.length;
    for (uint256 _i; _i < _inputLength; ) {
      lyfDs.tokenConfigs[_tokenConfigs[_i].token] = LibLYF01.TokenConfig({
        tier: _tokenConfigs[_i].tier,
        collateralFactor: _tokenConfigs[_i].collateralFactor,
        borrowingFactor: _tokenConfigs[_i].borrowingFactor,
        maxCollateral: _tokenConfigs[_i].maxCollateral,
        maxBorrow: _tokenConfigs[_i].maxBorrow,
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_tokenConfigs[_i].token)
      });

      unchecked {
        ++_i;
      }
    }
  }

  function setLPConfigs(LPConfigInput[] calldata _configs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 _len = _configs.length;
    for (uint256 _i; _i < _len; ) {
      lyfDs.lpConfigs[_configs[_i].lpToken] = LibLYF01.LPConfig({
        strategy: _configs[_i].strategy,
        masterChef: _configs[_i].masterChef,
        router: _configs[_i].router,
        rewardToken: _configs[_i].rewardToken,
        reinvestPath: _configs[_i].reinvestPath,
        reinvestThreshold: _configs[_i].reinvestThreshold,
        poolId: _configs[_i].poolId
      });
      unchecked {
        ++_i;
      }
    }
  }

  function setDebtShareId(
    address _token,
    address _lpToken,
    uint256 _debtShareId
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    // validate token must not alrready set
    // validate if token exist but different lp
    if (
      lyfDs.debtShareIds[_token][_lpToken] != 0 ||
      (lyfDs.debtShareTokens[_debtShareId] != address(0) && lyfDs.debtShareTokens[_debtShareId] != _token)
    ) {
      revert LYFAdminFacet_BadDebtShareId();
    }
    lyfDs.debtShareIds[_token][_lpToken] = _debtShareId;
    lyfDs.debtShareTokens[_debtShareId] = _token;
  }

  function setDebtInterestModel(uint256 _debtShareId, address _interestModel) external {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.interestModels[_debtShareId] = _interestModel;
  }

  function setMinDebtSize(uint256 _newValue) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.minDebtSize = _newValue;

    emit LogSetMinDebtSize(_newValue);
  }

  function setReinvestorsOk(address[] memory list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    for (uint256 _i; _i < _length; ) {
      lyfDs.reinvestorsOk[list[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }

  function setLiquidationStratsOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    for (uint256 _i; _i < _length; ) {
      lyfDs.liquidationStratOk[list[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }

  function setLiquidatorsOk(address[] calldata list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    for (uint256 _i; _i < _length; ) {
      lyfDs.liquidationCallersOk[list[_i]] = _isOk;
      unchecked {
        ++_i;
      }
    }
  }

  function setTreasury(address _newTreasury) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.treasury = _newTreasury;
  }

  function setMaxNumOfToken(uint8 _numOfCollat) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.maxNumOfCollatPerSubAccount = _numOfCollat;
    emit LogSetMaxNumOfToken(_numOfCollat);
  }

  /// @notice Withdraw the protocol's reserve
  /// @param _token The token to be withdrawn
  /// @param _to The destination address
  /// @param _amount The amount to withdraw
  function withdrawReserve(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    if (_amount > lyfDs.protocolReserves[_token]) {
      revert LYFAdminFacet_ReserveTooLow();
    }
    if (_amount > lyfDs.reserves[_token]) {
      revert LYFAdminFacet_NotEnoughToken();
    }

    lyfDs.protocolReserves[_token] -= _amount;

    lyfDs.reserves[_token] -= _amount;
    IERC20(_token).safeTransfer(_to, _amount);

    emit LogWitdrawReserve(_token, _to, _amount);
  }
}
