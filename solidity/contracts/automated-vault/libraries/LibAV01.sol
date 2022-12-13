// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libraries
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";

library LibAV01 {
  using SafeERC20 for ERC20;

  // keccak256("av.diamond.storage");
  bytes32 internal constant AV_STORAGE_POSITION = 0x7829d0c15b32d5078302aaa27ee1e42f0bdf275e05094cc17e0f59b048312982;

  struct ShareTokenConfig {
    uint256 someConfig; // TODO: replace with real config
  }

  struct AVDiamondStorage {
    mapping(address => address) tokenToShareToken;
    mapping(address => address) shareTokenToToken;
    mapping(address => ShareTokenConfig) shareTokenConfig;
  }

  error LibAV01_InvalidToken(address _token);
  error LibAV01_NoTinyShares();
  error LibAV01_TooLittleReceived();

  function getStorage() internal pure returns (AVDiamondStorage storage ds) {
    assembly {
      ds.slot := AV_STORAGE_POSITION
    }
  }

  function deposit(
    address _token,
    uint256 _amountIn,
    uint256 _minShareOut,
    AVDiamondStorage storage avDs
  ) internal {
    address _shareToken = avDs.tokenToShareToken[_token];
    if (_shareToken == address(0)) {
      revert LibAV01_InvalidToken(_token);
    }

    uint256 _totalShareTokenSupply = ERC20(_shareToken).totalSupply();
    // TODO: replace _amountIn getTotalToken by equity
    uint256 _totalToken = _amountIn;

    uint256 _shareToMint = LibShareUtil.valueToShare(_amountIn, _totalShareTokenSupply, _totalToken);
    if (_minShareOut > _shareToMint) {
      revert LibAV01_TooLittleReceived();
    }
    if (_totalShareTokenSupply + _shareToMint < 10**(ERC20(_shareToken).decimals()) - 1) {
      revert LibAV01_NoTinyShares();
    }

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
    IAVShareToken(_shareToken).mint(msg.sender, _shareToMint);
  }
}
