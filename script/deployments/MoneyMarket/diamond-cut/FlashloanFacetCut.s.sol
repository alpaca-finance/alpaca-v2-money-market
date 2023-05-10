// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IMMDiamondCut } from "solidity/contracts/money-market/interfaces/IMMDiamondCut.sol";
import { IFlashloanFacet } from "solidity/contracts/money-market/interfaces/IFlashloanFacet.sol";

contract DiamondCutFlashloanFacetScript is BaseScript {
  using stdJson for string;

  function run() public {
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    address flashloanFacet = 0x029dD6e7FaA03252d6c19240fA264d82a2556971;

    IMMDiamondCut.FacetCut[] memory facetCuts = new IMMDiamondCut.FacetCut[](1);

    facetCuts[0] = IMMDiamondCut.FacetCut({
      action: IMMDiamondCut.FacetCutAction.Add,
      facetAddress: flashloanFacet,
      functionSelectors: getFlashloanFacetSelectors()
    });

    _startDeployerBroadcast();

    IMMDiamondCut(address(moneyMarket)).diamondCut(facetCuts, address(0), "");

    _stopBroadcast();
  }

  function getFlashloanFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](1);
    _selectors[0] = IFlashloanFacet.flashloan.selector;
  }
}
