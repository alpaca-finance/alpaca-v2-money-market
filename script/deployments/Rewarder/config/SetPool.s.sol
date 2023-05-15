// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IRewarder } from "solidity/contracts/miniFL/interfaces/IRewarder.sol";

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

    IRewarder rewarder = IRewarder(0x767adcb3650BAB4FEA44469fCe3FA66D767Bc22c);

    setIbAllocPoint(wbnb, 75); // WBNB
    setDebtAllocPoint(wbnb, 100);
    // BTCB
    // setIbAllocPoint(btcb, 100);
    // setDebtAllocPoint(btcb, 125);
    // // USDT
    // setIbAllocPoint(usdt, 100);
    // setDebtAllocPoint(usdt, 175);
    // // ETH
    // setIbAllocPoint(eth, 75);
    // setDebtAllocPoint(eth, 100);
    // // USDC
    // setIbAllocPoint(usdc, 50);
    // setDebtAllocPoint(usdc, 75);
    // // BUSD
    // setIbAllocPoint(busd, 50);
    // setDebtAllocPoint(busd, 75);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < setPoolInputs.length; i++) {
      rewarder.setPool(setPoolInputs[i].pid, setPoolInputs[i].allocPoint, true);
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
