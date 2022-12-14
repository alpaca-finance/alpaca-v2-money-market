// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// interfaces
import { IAVFarmFacet } from "../interfaces/IAVFarmFacet.sol";
import { IAVShareToken } from "../interfaces/IAVShareToken.sol";

// libraries
import { LibAV01 } from "../libraries/LibAV01.sol";

contract AVFarmFacet is IAVFarmFacet {
  using SafeERC20 for ERC20;

  function deposit(
    address _token,
    uint256 _amountIn,
    uint256 _minShareOut
  ) external {
    LibAV01.AVDiamondStorage storage avDs = LibAV01.getStorage();
    LibAV01.deposit(_token, _amountIn, _minShareOut, avDs);
  }
}
