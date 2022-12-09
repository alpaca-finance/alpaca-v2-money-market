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
    lyfDs.oracle = IAlpacaV2Oracle(_oracle);
  }

  function oracle() external view returns (address) {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    return address(lyfDs.oracle);
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
        maxToleranceExpiredSecond: _tokenConfigs[_i].maxToleranceExpiredSecond,
        to18ConversionFactor: LibLYF01.to18ConversionFactor(_tokenConfigs[_i].token)
      });

      LibLYF01.setTokenConfig(_tokenConfigs[_i].token, _tokenConfig, lyfDs);

      unchecked {
        _i++;
      }
    }
  }

  function setMoneyMarket(address _moneyMarket) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    lyfDs.moneyMarket = _moneyMarket;
  }

  function setLPConfigs(LPConfigInput[] calldata _configs) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();

    uint256 len = _configs.length;
    for (uint256 i = 0; i < len; ) {
      lyfDs.lpConfigs[_configs[i].lpToken] = LibLYF01.LPConfig({
        strategy: _configs[i].strategy,
        masterChef: _configs[i].masterChef,
        router: _configs[i].router,
        rewardToken: _configs[i].rewardToken,
        reinvestPath: _configs[i].reinvestPath,
        reinvestThreshold: _configs[i].reinvestThreshold,
        poolId: _configs[i].poolId
      });
      unchecked {
        i++;
      }
    }
  }

  function setDebtShareId(
    address _token,
    address _lpToken,
    uint256 _debtShareId
  ) external onlyOwner {
    LibLYF01.LYFDiamondStorage storage lyfDs = LibLYF01.lyfDiamondStorage();
    if (lyfDs.debtShareIds[_token][_lpToken] == 0) {
      lyfDs.debtShareIds[_token][_lpToken] = _debtShareId;
      lyfDs.debtShareTokens[_debtShareId] = LibLYF01.DebtShareTokens({ token: _token, lpToken: _lpToken });
    }
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
        _i++;
      }
    }
  }
}
