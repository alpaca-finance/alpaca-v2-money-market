// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract SetPoolScript is BaseScript {
  struct SetPoolInput {
    uint256 pid;
    uint256 allocPoint;
  }

  SetPoolInput[] setPoolInputs;

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

    // ada
    setIbAllocPoint(ada, 10);
    setDebtAllocPoint(ada, 15);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < setPoolInputs.length; i++) {
      miniFL.setPool{ gas: 4_000_000 }(setPoolInputs[i].pid, setPoolInputs[i].allocPoint, true);
    }

    _stopBroadcast();
  }

  function setIbAllocPoint(address _token, uint256 _allocPoint) internal {
    address _ibToken = moneyMarket.getIbTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_ibToken);
    setPoolAllocPoint(_pid, _allocPoint);
  }

  function setDebtAllocPoint(address _token, uint256 _allocPoint) internal {
    address _debtToken = moneyMarket.getDebtTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_debtToken);
    setPoolAllocPoint(_pid, _allocPoint);
  }

  function setPoolAllocPoint(uint256 _pid, uint256 _allocPoint) internal {
    setPoolInputs.push(SetPoolInput({ pid: _pid, allocPoint: _allocPoint }));
  }
}
