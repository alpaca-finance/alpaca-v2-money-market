// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// libs
import { LibLYF01 } from "../libraries/LibLYF01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

import { ILYFAdminFacet } from "../interfaces/ILYFAdminFacet.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";

contract LYFAdminFacet is ILYFAdminFacet {
  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function setOracle(address _oracle) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.oracle = _oracle;
  }

  function setTokenConfigs(TokenConfigInput[] memory _tokenConfigs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _inputLength = _tokenConfigs.length;
    for (uint8 _i; _i < _inputLength; ) {
      LibLYF01.TokenConfig memory _tokenConfig = LibLYF01.TokenConfig({
        tier: _tokenConfigs[_i].tier,
        collateralFactor: _tokenConfigs[_i].collateralFactor,
        borrowingFactor: _tokenConfigs[_i].borrowingFactor,
        maxCollateral: _tokenConfigs[_i].maxCollateral,
        maxBorrow: _tokenConfigs[_i].maxBorrow,
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_tokenConfigs[_i].token)
      });

      LibLYF01.setTokenConfig(_tokenConfigs[_i].token, _tokenConfig, lyfDs);

      unchecked {
        ++_i;
      }
    }
  }

  function setMoneyMarket(address _moneyMarket) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.moneyMarket = _moneyMarket;
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

  function setReinvestorsOk(address[] memory list, bool _isOk) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    uint256 _length = list.length;
    for (uint8 _i; _i < _length; ) {
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
}
