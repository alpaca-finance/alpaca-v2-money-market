// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IAlpacaFlashloanCallback } from "../../contracts/money-market/interfaces/IAlpacaFlashloanCallback.sol";
import { IFlashloanFacet } from "../../contracts/money-market/interfaces/IFlashloanFacet.sol";
import { IERC20 } from "../../contracts/money-market/interfaces/IERC20.sol";

// repurchase
import { ILiquidationFacet } from "../../contracts/money-market/interfaces/ILiquidationFacet.sol";

contract MockFlashloan_Repurchase is IAlpacaFlashloanCallback {
  IFlashloanFacet internal immutable flashloanRouter;

  struct RepurchaseParam {
    address _account;
    uint256 _subAccountId;
    address _repayToken;
    address _collatToken;
    uint256 _desiredRepayAmount;
  }

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
    // repurchaser call repurchase via liquidation
    RepurchaseParam memory _param = abi.decode(_data, (RepurchaseParam));
    ILiquidationFacet(msg.sender).repurchase(
      _param._account,
      _param._subAccountId,
      _param._repayToken,
      _param._collatToken,
      _param._desiredRepayAmount
    );
    IERC20(_token).transfer(msg.sender, _repay);
  }
}
