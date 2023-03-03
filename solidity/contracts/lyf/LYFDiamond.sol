// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import { LibDiamond } from "./libraries/LibDiamond.sol";
import { ILYFDiamondCut } from "./interfaces/ILYFDiamondCut.sol";

contract LYFDiamond {
  constructor(address _contractOwner, address _LYFDiamondCutFacet) {
    LibDiamond.setContractOwner(_contractOwner);

    ILYFDiamondCut.FacetCut[] memory cut = new ILYFDiamondCut.FacetCut[](1);
    bytes4[] memory functionSelectors = new bytes4[](1);
    functionSelectors[0] = ILYFDiamondCut.diamondCut.selector;
    cut[0] = ILYFDiamondCut.FacetCut({
      facetAddress: _LYFDiamondCutFacet,
      action: ILYFDiamondCut.FacetCutAction.Add,
      functionSelectors: functionSelectors
    });
    LibDiamond.diamondCut(cut, address(0), "");
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
