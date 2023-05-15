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

    IRewarder rewarder = IRewarder(0x0886B13E413bc0fBAeDB76b0855CA5F2dae82E99);

    // WBNB
    addIbPool(wbnb, 75);
    addDebtPool(wbnb, 100);
    // BTCB
    addIbPool(btcb, 100);
    addDebtPool(btcb, 125);
    // USDT
    addIbPool(usdt, 100);
    addDebtPool(usdt, 175);
    // ETH
    addIbPool(eth, 75);
    addDebtPool(eth, 100);
    // USDC
    addIbPool(usdc, 50);
    addDebtPool(usdc, 75);
    // BUSD
    addIbPool(busd, 50);
    addDebtPool(busd, 75);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < addPoolInputs.length; i++) {
      rewarder.addPool(addPoolInputs[i].pid, addPoolInputs[i].allocPoint, true);
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
