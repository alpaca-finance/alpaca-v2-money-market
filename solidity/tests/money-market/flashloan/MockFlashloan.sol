// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IAlpacaFlashloan } from "../../../contracts/money-market/interfaces/IAlpacaFlashloan.sol";
import { IFlashloanFacet } from "../../../contracts/money-market/interfaces/IFlashloanFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

contract MockFlashloan is IAlpacaFlashloan {
  function flash(
    address _flashloanRouter,
    address _token,
    uint256 _amount
  ) external {
    IFlashloanFacet(_flashloanRouter).flashloan(_token, _amount);
  }

  function AlpacaFlashloanCallback(address _token, uint256 _amount) external {
    IERC20(_token).transfer(msg.sender, _amount * 2);
  }
}
