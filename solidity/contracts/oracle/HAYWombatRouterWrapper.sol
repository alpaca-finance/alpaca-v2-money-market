// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IWombatRouter } from "./interfaces/IWombatRouter.sol";

contract HAYWombatRouterWrapper {
  address public constant HAY_SMART_POOL = 0xa61dccC6c6E34C8Fbf14527386cA35589e9b8C27;
  address public constant HAY = 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5;
  IWombatRouter public constant router = IWombatRouter(0x19609B03C976CCA288fbDae5c21d4290e9a4aDD7);

  function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
    require(path[0] == 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5, "!HAY");
    amounts = new uint256[](2);
    amounts[0] = amountIn;
    address[] memory _poolPath = new address[](1);
    _poolPath[0] = HAY_SMART_POOL;

    (amounts[1], ) = router.getAmountOut(path, _poolPath, int256(amountIn));
  }
}
