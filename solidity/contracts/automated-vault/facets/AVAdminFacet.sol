// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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

  function setTokensToShareTokens(ShareTokenPairs[] calldata pairs) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();

    uint256 length = pairs.length;
    for (uint256 i; i < length; ) {
      ShareTokenPairs calldata pair = pairs[i];
      avDs.tokenToShareToken[pair.token] = pair.shareToken;
      avDs.shareTokenToToken[pair.shareToken] = pair.token;
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
      avDs.shareTokenConfig[config.shareToken] = LibAV01.ShareTokenConfig({ someConfig: config.someConfig });
      unchecked {
        i++;
      }
    }
  }

  function setAVHandler(address _handler) external onlyOwner {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    avDs.handler = _handler;
  }
}
