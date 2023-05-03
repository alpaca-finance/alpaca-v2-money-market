// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// interfaces
import { IMMDiamondLoupe } from "./interfaces/IMMDiamondLoupe.sol";
import { IMMDiamondCut } from "./interfaces/IMMDiamondCut.sol";
import { IMiniFL } from "./interfaces/IMiniFL.sol";
import { IERC173 } from "./interfaces/IERC173.sol";
import { IERC165 } from "./interfaces/IERC165.sol";

// libraries
import { LibDiamond } from "./libraries/LibDiamond.sol";
import { LibMoneyMarket01 } from "./libraries/LibMoneyMarket01.sol";

contract MoneyMarketDiamond {
  error MoneyMarketDiamond_InvalidAddress();

  constructor(address _diamondCutFacet, address _miniFL) {
    // set contract owner
    LibDiamond.setContractOwner(msg.sender);

    // register DiamondCut facet
    IMMDiamondCut.FacetCut[] memory cut = new IMMDiamondCut.FacetCut[](1);
    bytes4[] memory functionSelectors = new bytes4[](1);
    functionSelectors[0] = IMMDiamondCut.diamondCut.selector;
    cut[0] = IMMDiamondCut.FacetCut({
      facetAddress: _diamondCutFacet,
      action: IMMDiamondCut.FacetCutAction.Add,
      functionSelectors: functionSelectors
    });
    LibDiamond.diamondCut(cut, address(0), "");

    // adding ERC165 data
    LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
    ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    ds.supportedInterfaces[type(IMMDiamondCut).interfaceId] = true;
    ds.supportedInterfaces[type(IMMDiamondLoupe).interfaceId] = true;
    ds.supportedInterfaces[type(IERC173).interfaceId] = true;

    // initialize money market states
    LibMoneyMarket01.MoneyMarketDiamondStorage storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();
    moneyMarketDs.miniFL = IMiniFL(_miniFL);
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
