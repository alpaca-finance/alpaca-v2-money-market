// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AVShareToken } from "../AVShareToken.sol";

// interfaces
import { IAVAdminFacet } from "../interfaces/IAVAdminFacet.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

contract AVAdminFacet is IAVAdminFacet {
  modifier onlyOwner() {
    LibDiamond.enforceIsContractOwner();
    _;
  }

  function openVault(address _token) external onlyOwner returns (address _newShareToken) {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    if (avDs.tokenToShareToken[_token] != address(0)) {
      revert AVTradeFacet_InvalidToken(_token);
    }

    string memory _tokenSymbol = ERC20(_token).symbol();
    uint8 _tokenDecimals = ERC20(_token).decimals();
    _newShareToken = address(
      new AVShareToken(
        string.concat("Share Token ", _tokenSymbol),
        string.concat("Share ", _tokenSymbol),
        _tokenDecimals
      )
    );

    LibAV01.setShareTokenPair(_token, _newShareToken, avDs);

    // TODO: set config

    emit LogOpenMarket(msg.sender, _token, _newShareToken);
  }

  function setTokensToShareTokens(ShareTokenPairs[] calldata pairs) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    uint256 length = pairs.length;
    for (uint256 i; i < length; ) {
      ShareTokenPairs calldata pair = pairs[i];
      LibAV01.setShareTokenPair(pair.token, pair.shareToken, avDs);
      unchecked {
        i++;
      }
    }
  }

  function setShareTokenConfigs(ShareTokenConfigInput[] calldata configs) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    uint256 length = configs.length;
    for (uint256 i; i < length; ) {
      ShareTokenConfigInput calldata config = configs[i];
      avDs.shareTokenConfig[config.shareToken] = LibAV01.ShareTokenConfig({ lpToken: config.lpToken });
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
    avDs.oracle = _oracle;
  }

  function setAVHandler(address _shareToken, address avHandler) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    if (avDs.shareTokenToToken[_shareToken] == address(0)) revert AVAdminFacet_InvalidShareToken(_shareToken);
    avDs.avHandlers[_shareToken] = avHandler;
  }
}
