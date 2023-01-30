// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockLPToken is ERC20 {
  uint8 internal _decimals;
  address public token0;
  address public token1;

  constructor(
    string memory name,
    string memory symbol,
    uint8 __decimals,
    address _token0,
    address _token1
  ) ERC20(name, symbol) {
    _decimals = __decimals;
    token0 = _token0;
    token1 = _token1;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function getReserves()
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 _token0Decimal = ERC20(token0).decimals();
    uint256 _token1Decimal = ERC20(token1).decimals();
    return (1e30 / 10**(18 - _token0Decimal), 1e30 / 10**(18 - _token1Decimal), 0);
  }
}
