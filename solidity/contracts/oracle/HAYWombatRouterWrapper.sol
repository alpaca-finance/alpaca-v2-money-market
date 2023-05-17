// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IWombatRouter } from "./interfaces/IWombatRouter.sol";

contract HAYWombatRouterWrapper {
  address public constant HAY_SMART_POOL = 0xa61dccC6c6E34C8Fbf14527386cA35589e9b8C27;
  address public constant HAY_POOL = 0x0520451B19AD0bb00eD35ef391086A692CFC74B2;
  address public constant MAIN_POOL = 0x312Bc7eAAF93f1C60Dc5AfC115FcCDE161055fb0;

  address public constant HAY = 0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5;
  address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

  IWombatRouter public constant router = IWombatRouter(0x19609B03C976CCA288fbDae5c21d4290e9a4aDD7);

  function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
    require(path[0] == HAY, "!HAY");
    require(path[1] == BUSD, "!BUSD");

    amounts = new uint256[](2);
    amounts[0] = amountIn;
    address[] memory _poolPath = new address[](2);
    _poolPath[0] = HAY_POOL;
    _poolPath[1] = MAIN_POOL;

    (amounts[1], ) = router.getAmountOut(path, _poolPath, int256(amountIn));
  }
}
