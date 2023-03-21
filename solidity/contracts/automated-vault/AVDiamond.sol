// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { LibDiamond } from "./libraries/LibDiamond.sol";
import { IAVDiamondCut } from "./interfaces/IAVDiamondCut.sol";
import { IAVDiamondLoupe } from "./interfaces/IAVDiamondLoupe.sol";
import { IAVAdminFacet } from "./interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "./interfaces/IAVTradeFacet.sol";
import { IAVViewFacet } from "./interfaces/IAVViewFacet.sol";
import { IERC173 } from "./interfaces/IERC173.sol";
import { IERC165 } from "./interfaces/IERC165.sol";

contract AVDiamond {
  constructor(address _AVDiamondCutFacet) {
    LibDiamond.setContractOwner(msg.sender);

    IAVDiamondCut.FacetCut[] memory cut = new IAVDiamondCut.FacetCut[](1);
    bytes4[] memory functionSelectors = new bytes4[](1);
    functionSelectors[0] = IAVDiamondCut.diamondCut.selector;
    cut[0] = IAVDiamondCut.FacetCut({
      facetAddress: _AVDiamondCutFacet,
      action: IAVDiamondCut.FacetCutAction.Add,
      functionSelectors: functionSelectors
    });
    LibDiamond.diamondCut(cut, address(0), "");

    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    ds.supportedInterfaces[type(IAVDiamondCut).interfaceId] = true;
    ds.supportedInterfaces[type(IAVDiamondLoupe).interfaceId] = true;
    ds.supportedInterfaces[type(IERC173).interfaceId] = true;

    // add others facets
    // todo: add AV facets interface
    ds.supportedInterfaces[type(IAVAdminFacet).interfaceId] = true;
  }

  // Find facet for function that is called and execute the
  // function if a facet is found and return any value.
  fallback() external payable {
    LibDiamond.DiamondStorage storage ds;
    bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
    // get diamond storage
    assembly {
      ds.slot := position
    }
    // get facet from function selector
    address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
    require(facet != address(0), "Diamond: Function does not exist");
    // Execute external function from facet using delegatecall and return any value.
    assembly {
      // copy function selector and any arguments
      calldatacopy(0, 0, calldatasize())
      // execute function call using the facet
      let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
      // get any return value
      returndatacopy(0, 0, returndatasize())
      // return any return value or error back to the caller
      switch result
      case 0 {
        revert(0, returndatasize())
      }
      default {
        return(0, returndatasize())
      }
    }
  }

  receive() external payable {}
}
