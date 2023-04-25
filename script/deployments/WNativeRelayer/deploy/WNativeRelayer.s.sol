pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IWNativeRelayer } from "solidity/contracts/interfaces/IWNativeRelayer.sol";

contract DeployWNativeRelayerScript is BaseScript {
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

    address _wNativeToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./script/deployments/WNativeRelayer/deploy/WNativeRelayer.json"),
      abi.encode(_wNativeToken)
    );

    address _nativeRelayer;
    _startDeployerBroadcast();

    assembly {
      _nativeRelayer := create(0, add(_logicBytecode, 0x20), mload(_logicBytecode))
      if iszero(extcodesize(_nativeRelayer)) {
        revert(0, 0)
      }
    }
    _stopBroadcast();

    console.log("_nativeRelayer", _nativeRelayer);
  }
}
