// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IAlpacaFlashloanCallback } from "../../../contracts/money-market/interfaces/IAlpacaFlashloanCallback.sol";
import { IFlashloanFacet } from "../../../contracts/money-market/interfaces/IFlashloanFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";

contract MockFlashloan is IAlpacaFlashloanCallback {
  IFlashloanFacet internal immutable flashloanRouter;

  constructor(address _flashloanRouter) {
    flashloanRouter = IFlashloanFacet(_flashloanRouter);
  }

  function flash(
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external {
    flashloanRouter.flashloan(_token, _amount, _data);
  }

  function alpacaFlashloanCallback(
    address _token,
    uint256 _repay,
    bytes calldata _data
  ) external {
    if (_data.length == 0) {
      IERC20(_token).transfer(msg.sender, _repay);
    } else {
      (bool _sign, uint256 _fee) = abi.decode(_data, (bool, uint256));

      // if sign is true => excess case
      if (_sign) {
        IERC20(_token).transfer(msg.sender, _repay + _fee);
      }

      // if sign is false => lack case
      if (!_sign) {
        IERC20(_token).transfer(msg.sender, _repay - _fee);
      }
    }
  }
}
