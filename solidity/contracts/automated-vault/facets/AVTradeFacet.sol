// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { AVShareToken } from "../AVShareToken.sol";

// interfaces
import { IAVTradeFacet } from "../interfaces/IAVTradeFacet.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVTradeFacet is IAVTradeFacet {
  using SafeERC20 for ERC20;

  function openVault(address _token) external returns (address _newShareToken) {
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

  function deposit(
    address _token,
    uint256 _amountIn,
    uint256 _minShareOut
  ) external {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    LibAV01.deposit(_token, _amountIn, _minShareOut, avDs);
  }
}
