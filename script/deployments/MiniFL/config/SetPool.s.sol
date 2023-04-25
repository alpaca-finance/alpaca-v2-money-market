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

    // WBNB
    setIbAllocPoint(wbnb, 125);
    setDebtAllocPoint(wbnb, 50);
    // BTCB
    setIbAllocPoint(btcb, 225);
    setDebtAllocPoint(btcb, 50);
    // USDT
    setIbAllocPoint(btcb, 175);
    setDebtAllocPoint(btcb, 100);
    // ETH
    setIbAllocPoint(eth, 100);
    setDebtAllocPoint(eth, 25);
    // USDC
    setIbAllocPoint(usdc, 75);
    setDebtAllocPoint(usdc, 50);
    // BUSD
    setIbAllocPoint(busd, 50);
    setDebtAllocPoint(busd, 50);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < setPoolInputs.length; i++) {
      miniFL.setPool(setPoolInputs[i].pid, setPoolInputs[i].allocPoint, false);
    }

    _stopBroadcast();
  }

  function setIbAllocPoint(address _token, uint256 _allocaPoint) internal {
    address _ibToken = moneyMarket.getIbTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_ibToken);
    setPoolAllocPoint(_pid, _allocaPoint);
  }

  function setDebtAllocPoint(address _token, uint256 _allocaPoint) internal {
    address _debtToken = moneyMarket.getDebtTokenFromToken(_token);
    uint256 _pid = moneyMarket.getMiniFLPoolIdOfToken(_debtToken);
    setPoolAllocPoint(_pid, _allocaPoint);
  }

  function setPoolAllocPoint(uint256 _pid, uint256 _allocPoint) internal {
    setPoolInputs.push(SetPoolInput({ pid: _pid, allocPoint: _allocPoint }));
  }
}
