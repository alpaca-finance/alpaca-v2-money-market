// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseFork } from "./BaseFork.sol";
import { ISmartTreasury } from "solidity/contracts/interfaces/ISmartTreasury.sol";

contract SmartTreasury_Withdraw is BaseFork {
  function setUp() public override {
    super.setUp();
  }

  function testCorrectness_Withdraw_ShouldWork() external {
    // top up
    uint256 _topUpAmount = normalizeEther(10 ether, wbnb.decimals());
    deal(address(wbnb), address(smartTreasury), _topUpAmount);
    uint256 _deployerBalance = wbnb.balanceOf(DEPLOYER);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    vm.prank(DEPLOYER);
    smartTreasury.withdraw(_tokens, DEPLOYER);

    uint256 _deployerAfter = wbnb.balanceOf(DEPLOYER);
    assertEq(_deployerAfter, _deployerBalance + _topUpAmount, "DEPLOYER BALANCE");
  }

  function testRevert_UnauthorizedWithdraw_ShouldRevert() external {
    // top up
    uint256 _topUpAmount = normalizeEther(10 ether, wbnb.decimals());
    deal(address(wbnb), address(smartTreasury), _topUpAmount);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(wbnb);

    vm.prank(BOB);
    vm.expectRevert("Ownable: caller is not the owner");
    smartTreasury.withdraw(_tokens, DEPLOYER);
  }
}
