// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IRewarder } from "solidity/contracts/miniFL/interfaces/IRewarder.sol";

contract SetPoolScript is BaseScript {
  struct AddPoolInput {
    uint256 pid;
    uint256 allocPoint;
  }

  AddPoolInput[] addPoolInputs;

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

    IRewarder rewarder = IRewarder(0x5706ef757a635A986032cfe14e7B12EBA9f118Fd);

    // THE
    addIbPool(the, 40);
    addDebtPool(the, 60);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < addPoolInputs.length; i++) {
      rewarder.addPool{ gas: 4_000_000 }(addPoolInputs[i].pid, addPoolInputs[i].allocPoint, true);
    }

    _stopBroadcast();
  }

  function addIbPool(address _token, uint256 _allocPoint) internal {
    address _ibToken = moneyMarket.getIbTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_ibToken);
    addRewarderPool(_pid, _allocPoint);
  }

  function addDebtPool(address _token, uint256 _allocPoint) internal {
    address _debtToken = moneyMarket.getDebtTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_debtToken);
    addRewarderPool(_pid, _allocPoint);
  }

  function addRewarderPool(uint256 _pid, uint256 _allocPoint) internal {
    addPoolInputs.push(AddPoolInput({ pid: _pid, allocPoint: _allocPoint }));
  }
}
