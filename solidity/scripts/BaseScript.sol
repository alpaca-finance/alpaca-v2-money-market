// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "solidity/tests/utils/StdJson.sol";
import { Script, console } from "solidity/tests/utils/Script.sol";

// libs
import { LibMoneyMarketDeployment } from "./deployments/libraries/LibMoneyMarketDeployment.sol";

// interfaces
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";
import { IViewFacet } from "solidity/contracts/money-market/interfaces/IViewFacet.sol";
import { ICollateralFacet } from "solidity/contracts/money-market/interfaces/ICollateralFacet.sol";
import { IBorrowFacet } from "solidity/contracts/money-market/interfaces/IBorrowFacet.sol";
import { ILendFacet } from "solidity/contracts/money-market/interfaces/ILendFacet.sol";
import { IOwnershipFacet } from "solidity/contracts/money-market/interfaces/IOwnershipFacet.sol";
import { IMiniFL } from "solidity/contracts/miniFL/interfaces/IMiniFL.sol";

// mocks
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";

interface IMoneyMarket is IAdminFacet, IViewFacet, ICollateralFacet, IBorrowFacet, ILendFacet, IOwnershipFacet {}

abstract contract BaseScript is Script {
  using stdJson for string;

  uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
  uint256 internal userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
  string internal configFilePath =
    string.concat(vm.projectRoot(), string.concat("/configs/", vm.envString("DEPLOYMENT_CONFIG_FILENAME")));

  IMoneyMarket internal moneyMarket;
  IMiniFL internal miniFL;
  address internal deployerAddress;
  address internal userAddress;
  address internal proxyAdminAddress;

  function _loadAddresses() internal {
    deployerAddress = vm.addr(deployerPrivateKey);
    userAddress = vm.addr(userPrivateKey);

    string memory configJson = vm.readFile(configFilePath);
    moneyMarket = abi.decode(configJson.parseRaw(".moneyMarket.moneyMarketDiamond"), (IMoneyMarket));
    proxyAdminAddress = abi.decode(configJson.parseRaw(".proxyAdmin"), (address));
    miniFL = abi.decode(configJson.parseRaw(".miniFL.proxy"), (IMiniFL));
  }

  // function _pretendMM() internal {
  //   MoneyMarketConfig memory mmConfig = _getMoneyMarketConfig();
  //   address _moneyMarketDiamond = mmConfig.moneyMarketDiamond;
  //   // setup mm if not exist for local simulation
  //   uint256 size;
  //   assembly {
  //     size := extcodesize(_moneyMarketDiamond)
  //   }
  //   if (size > 0) {
  //     moneyMarket = IMoneyMarket(_moneyMarketDiamond);
  //   } else {
  //     vm.startPrank(deployerAddress);
  //     (_moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(1), address(2));
  //     vm.stopPrank();
  //     moneyMarket = IMoneyMarket(_moneyMarketDiamond);
  //   }
  // }

  function _setUpMockToken(string memory symbol, uint8 decimals) internal returns (address) {
    address newToken = address(new MockERC20("", symbol, decimals));
    vm.label(newToken, symbol);
    return newToken;
  }

  function _startDeployerBroadcast() internal {
    vm.startBroadcast(deployerPrivateKey);
    console.log("");
    console.log("==== start broadcast as deployer ====");
  }

  function _startUserBroadcast() internal {
    vm.startBroadcast(userPrivateKey);
    console.log("");
    console.log("==== start broadcast as user ====");
  }

  function _stopBroadcast() internal {
    vm.stopBroadcast();
    console.log("==== broadcast stopped ====\n");
  }

  function _writeJson(string memory serializedJson, string memory path) internal {
    serializedJson.write(configFilePath, path);
  }
}
