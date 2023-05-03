// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IAlpacaFlashloanCallback } from "../../../contracts/money-market/interfaces/IAlpacaFlashloanCallback.sol";
import { IFlashloanFacet } from "../../../contracts/money-market/interfaces/IFlashloanFacet.sol";
import { IERC20 } from "../../../contracts/money-market/interfaces/IERC20.sol";
import { IMoneyMarketAccountManager } from "../../../contracts/interfaces/IMoneyMarketAccountManager.sol";
import { ILendFacet } from "../../../contracts/money-market/interfaces/ILendFacet.sol";

contract MockFlashloan_Redeposit is IAlpacaFlashloanCallback {
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
    if (_data.length > 0) {
      (address _accountManager, uint256 _amount) = abi.decode(_data, (address, uint256));
      IERC20(_token).approve(_accountManager, type(uint256).max);
      IMoneyMarketAccountManager(_accountManager).deposit(_token, _amount);
      IERC20(_token).transfer(msg.sender, _repay);
    } else {
      IERC20(_token).approve(msg.sender, type(uint256).max);
      ILendFacet(msg.sender).deposit(address(this), _token, _repay);
      IERC20(_token).transfer(msg.sender, _repay);
    }
  }
}
