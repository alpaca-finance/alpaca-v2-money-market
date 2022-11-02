pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// interfaces
import { IIbToken } from "./interfaces/IIbToken.sol";

contract IbToken is ERC20, IIbToken {
  constructor(
    string memory name,
    string memory symbol
  ) public ERC20(name, symbol) {
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }
}
