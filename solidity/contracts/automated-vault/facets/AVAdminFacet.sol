// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AVShareToken } from "../AVShareToken.sol";

// interfaces
import { IAVAdminFacet } from "../interfaces/IAVAdminFacet.sol";
import { IAlpacaV2Oracle } from "../interfaces/IAlpacaV2Oracle.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

contract AVAdminFacet is IAVAdminFacet {
  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function openVault(
    address _lpToken,
    address _stableToken,
    address _assetToken,
    uint8 _leverageLevel,
    uint16 _managementFeePerSec
  ) external onlyOwner returns (address _newShareToken) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    string memory _tokenSymbol = ERC20(_lpToken).symbol();
    uint8 _tokenDecimals = ERC20(_lpToken).decimals();
    _newShareToken = address(
      new AVShareToken(
        string.concat("Share Token ", _tokenSymbol),
        string.concat("Share ", _tokenSymbol),
        _tokenDecimals
      )
    );

    avDs.vaultConfigs[_newShareToken] = LibAV01.VaultConfig({
      shareToken: _newShareToken,
      lpToken: _lpToken,
      stableToken: _stableToken,
      assetToken: _assetToken,
      leverageLevel: _leverageLevel,
      managementFeePerSec: _managementFeePerSec
    });

    emit LogOpenVault(msg.sender, _lpToken, _stableToken, _assetToken, _newShareToken);
  }

  function setTokenConfigs(TokenConfigInput[] calldata configs) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    uint256 length = configs.length;
    for (uint256 i; i < length; ) {
      TokenConfigInput calldata config = configs[i];
      avDs.tokenConfigs[config.token] = LibAV01.TokenConfig({
        tier: config.tier,
        maxToleranceExpiredSecond: config.maxToleranceExpiredSecond,
        to18ConversionFactor: LibAV01.to18ConversionFactor(config.token)
      });
      unchecked {
        i++;
      }
    }
  }

  function setMoneyMarket(address _newMoneyMarket) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    avDs.moneyMarket = _newMoneyMarket;
  }

  function setOracle(address _oracle) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    avDs.oracle = IAlpacaV2Oracle(_oracle);
  }

  function setTreasury(address _treasury) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    avDs.treasury = _treasury;
  }
}
