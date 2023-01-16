// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// interfaces
import { IAVVaultToken } from "./interfaces/IAVVaultToken.sol";

// TODO: discuss usage of Ownable. we only need onlyVault and not other ownership functions Ownable provided
contract AVVaultToken is ERC20, IAVVaultToken, Ownable {
  uint8 private _decimals;

  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimals_
  ) ERC20(name_, symbol_) {
    _decimals = decimals_;
  }

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external onlyOwner {
    _burn(from, amount);
  }

  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }
}
