// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// util
import { VM } from "solidity/tests/utils/VM.sol";

import { AVDiamond } from "../../contracts/automated-vault/AVDiamond.sol";

// facets
import { IAVDiamondCut } from "../../contracts/automated-vault/interfaces/IAVDiamondCut.sol";
import { IAVDiamondLoupe } from "../../contracts/automated-vault/interfaces/IAVDiamondLoupe.sol";
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";
import { IAVViewFacet } from "../../contracts/automated-vault/interfaces/IAVViewFacet.sol";

library AVDiamondDeployer {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  struct FacetAddresses {
    address diamondCutFacet;
    address diamondLoupeFacet;
    address viewFacet;
    address tradeFacet;
    address rebalanceFacet;
    address adminFacet;
  }

  function deployAVDiamond() internal returns (address _avDiamond, FacetAddresses memory _facetAddresses) {
    // deploy facets
    _facetAddresses = deployAVFacets();

    // deploy AVDiamond
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/AVDiamond.sol/AVDiamond.json"),
      abi.encode(_facetAddresses.diamondCutFacet)
    );

    assembly {
      _avDiamond := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_avDiamond)) {
        revert(0, 0)
      }
    }

    // do diamondCut
    diamondCutAllAVFacets(_avDiamond, _facetAddresses);

    return (_avDiamond, _facetAddresses);
  }

  function deployAVFacets() internal returns (FacetAddresses memory _facetAddresses) {
    _facetAddresses.diamondCutFacet = deployContract("./out/AVDiamondCutFacet.sol/AVDiamondCutFacet.json");
    _facetAddresses.diamondLoupeFacet = deployContract("./out/AVDiamondLoupeFacet.sol/AVDiamondLoupeFacet.json");
    _facetAddresses.viewFacet = deployContract("./out/AVViewFacet.sol/AVViewFacet.json");
    _facetAddresses.tradeFacet = deployContract("./out/AVTradeFacet.sol/AVTradeFacet.json");
    _facetAddresses.rebalanceFacet = deployContract("./out/AVRebalanceFacet.sol/AVRebalanceFacet.json");
    _facetAddresses.adminFacet = deployContract("./out/AVAdminFacet.sol/AVAdminFacet.json");
  }

  function diamondCutAllAVFacets(address _lyf, FacetAddresses memory _facetAddresses) internal {
    // prepare _selectors
    bytes4[] memory _diamondLoupeFacetSelectors = getAVDiamondLoupeFacetSelectors();
    bytes4[] memory _viewFacetSelectors = getAVViewFacetSelectors();
    bytes4[] memory _tradeFacetSelectors = getAVTradeFacetSelectors();
    bytes4[] memory _adminFacetSelectors = getAVAdminFacetSelectors();
    bytes4[] memory _rebalanceFacetSelectors = getAVRebalanceFacetSelectors();

    // prepare FacetCuts
    IAVDiamondCut.FacetCut[] memory _facetCuts = new IAVDiamondCut.FacetCut[](5);
    _facetCuts[0] = IAVDiamondCut.FacetCut({
      action: IAVDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.diamondLoupeFacet,
      functionSelectors: _diamondLoupeFacetSelectors
    });
    _facetCuts[1] = IAVDiamondCut.FacetCut({
      action: IAVDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.viewFacet,
      functionSelectors: _viewFacetSelectors
    });
    _facetCuts[2] = IAVDiamondCut.FacetCut({
      action: IAVDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.tradeFacet,
      functionSelectors: _tradeFacetSelectors
    });
    _facetCuts[3] = IAVDiamondCut.FacetCut({
      action: IAVDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.adminFacet,
      functionSelectors: _adminFacetSelectors
    });
    _facetCuts[4] = IAVDiamondCut.FacetCut({
      action: IAVDiamondCut.FacetCutAction.Add,
      facetAddress: _facetAddresses.rebalanceFacet,
      functionSelectors: _rebalanceFacetSelectors
    });

    // perform diamond cut on deployed MoneyMarketDiamond
    // address(0) and empty string means no initialization / cleanup after diamond cut
    IAVDiamondCut(_lyf).diamondCut(_facetCuts, address(0), "");
  }

  function getAVDiamondLoupeFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = IAVDiamondLoupe.facets.selector;
    _selectors[1] = IAVDiamondLoupe.facetFunctionSelectors.selector;
    _selectors[2] = IAVDiamondLoupe.facetAddresses.selector;
    _selectors[3] = IAVDiamondLoupe.facetAddress.selector;
  }

  function getAVAdminFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](10);
    _selectors[0] = IAVAdminFacet.openVault.selector;
    _selectors[1] = IAVAdminFacet.setTokenConfigs.selector;
    _selectors[2] = IAVAdminFacet.setOracle.selector;
    _selectors[3] = IAVAdminFacet.setMoneyMarket.selector;
    _selectors[4] = IAVAdminFacet.setTreasury.selector;
    _selectors[5] = IAVAdminFacet.setManagementFeePerSec.selector;
    _selectors[6] = IAVAdminFacet.setInterestRateModels.selector;
    _selectors[7] = IAVAdminFacet.setOperatorsOk.selector;
    _selectors[8] = IAVAdminFacet.setRepurchaseRewardBps.selector;
    _selectors[9] = IAVAdminFacet.setRepurchasersOk.selector;
  }

  function getAVTradeFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = IAVTradeFacet.deposit.selector;
    _selectors[1] = IAVTradeFacet.withdraw.selector;
  }

  function getAVRebalanceFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](2);
    _selectors[0] = IAVRebalanceFacet.retarget.selector;
    _selectors[1] = IAVRebalanceFacet.repurchase.selector;
  }

  function getAVViewFacetSelectors() internal pure returns (bytes4[] memory _selectors) {
    _selectors = new bytes4[](4);
    _selectors[0] = IAVViewFacet.getDebtValues.selector;
    _selectors[1] = IAVViewFacet.getPendingInterest.selector;
    _selectors[2] = IAVViewFacet.getLastAccrueInterestTimestamp.selector;
    _selectors[3] = IAVViewFacet.getPendingManagementFee.selector;
  }

  function buildFacetCut(
    address facet,
    IAVDiamondCut.FacetCutAction cutAction,
    bytes4[] memory selectors
  ) internal pure returns (IAVDiamondCut.FacetCut[] memory) {
    IAVDiamondCut.FacetCut[] memory facetCuts = new IAVDiamondCut.FacetCut[](1);
    facetCuts[0] = IAVDiamondCut.FacetCut({ action: cutAction, facetAddress: facet, functionSelectors: selectors });

    return facetCuts;
  }

  function deployContract(string memory _path) internal returns (address _deployedAddress) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode(_path));

    assembly {
      _deployedAddress := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_deployedAddress)) {
        revert(0, 0)
      }
    }
  }
}
