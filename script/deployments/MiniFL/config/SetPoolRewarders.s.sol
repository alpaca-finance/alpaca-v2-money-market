// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

contract SetPoolRewardersScript is BaseScript {
  struct SetPoolRewarderInput {
    uint256 pId;
    address[] rewarders;
  }

  SetPoolRewarderInput[] setPoolRewarderInputs;

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

    address[] memory rewarders = new address[](1);
    rewarders[0] = 0x5706ef757a635A986032cfe14e7B12EBA9f118Fd;

    setIbPoolRewarders(the, rewarders);
    setDebtPoolRewarders(the, rewarders);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < setPoolRewarderInputs.length; i++) {
      miniFL.setPoolRewarders(setPoolRewarderInputs[i].pId, setPoolRewarderInputs[i].rewarders);

      writeRewarderToMiniFLPool(setPoolRewarderInputs[i].pId, setPoolRewarderInputs[i].rewarders);
    }

    _stopBroadcast();
  }

  function setIbPoolRewarders(address _token, address[] memory _rewarders) internal {
    address _ibToken = moneyMarket.getIbTokenFromToken(_token);
    uint256 _pId = moneyMarket.getMiniFLPoolIdOfToken(_ibToken);
    setPoolRewarders(_pId, _rewarders);
  }

  function setDebtPoolRewarders(address _token, address[] memory _rewarders) internal {
    address _debtToken = moneyMarket.getDebtTokenFromToken(_token);
    uint256 _pId = moneyMarket.getMiniFLPoolIdOfToken(_debtToken);
    setPoolRewarders(_pId, _rewarders);
  }

  function setPoolRewarders(uint256 _pId, address[] memory _rewarders) internal {
    setPoolRewarderInputs.push(SetPoolRewarderInput({ pId: _pId, rewarders: _rewarders }));
  }

  function writeRewarderToMiniFLPool(uint256 _pId, address[] memory _rewarders) internal {
    uint256 rewardersLength = _rewarders.length;
    string[] memory cmds = new string[](6 + rewardersLength);
    cmds[0] = "npx";
    cmds[1] = "ts-node";
    cmds[2] = "./type-script/scripts/set-mini-fl-pool-rewarders.ts";
    cmds[3] = "--pid";
    cmds[4] = vm.toString(_pId);
    cmds[5] = "--rewarderAddress";

    for (uint256 i; i < rewardersLength; i++) {
      cmds[6 + i] = vm.toString(_rewarders[i]);
    }

    vm.ffi(cmds);
  }
}
