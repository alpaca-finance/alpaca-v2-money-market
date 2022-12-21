// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { MiniFL_BaseTest } from "./MiniFL_BaseTest.t.sol";

import { Rewarder } from "../../contracts/miniFL/Rewarder.sol";

// interfaces
import { IMiniFL } from "../../contracts/miniFL/interfaces/IMiniFL.sol";

contract MiniFL_DepositWithRewarderTest is MiniFL_BaseTest {
  uint256 wethPoolID = 0;
  uint256 debtTokenPoolID = 1;

  uint256 amountToDeposit = 10 ether;

  function setUp() public override {
    super.setUp();

    miniFL.addPool(100, IERC20Upgradeable(address(weth)), false, false);
    miniFL.addPool(100, IERC20Upgradeable(address(debtToken1)), true, false);

    // set debtToken staker
    uint256[] memory _poolIds = new uint256[](1);
    _poolIds[0] = debtTokenPoolID;
    address[] memory _stakers = new address[](1);
    _stakers[0] = BOB;
    miniFL.approveStakeDebtToken(_poolIds, _stakers, true);
    debtToken1.mint(BOB, 1000 ether);

    // rewarder
    address[] memory _poolWethRewarders = new address[](2);
    _poolWethRewarders[0] = address(rewarder1);
    _poolWethRewarders[1] = address(rewarder2);
    miniFL.setPoolRewarders(wethPoolID, _poolWethRewarders);
    rewarder1.addPool(100, wethPoolID, false);
    rewarder2.addPool(100, wethPoolID, false);

    address[] memory _poolDebtTokenRewarders = new address[](1);
    _poolDebtTokenRewarders[0] = address(rewarder1);
    miniFL.setPoolRewarders(debtTokenPoolID, _poolDebtTokenRewarders);
    rewarder1.addPool(100, debtTokenPoolID, false);
  }

  function testCorrectness_WhenDeposit_RewarderUserInfoShouldBeCorrect() external {
    uint256 _aliceWethBalanceBefore = weth.balanceOf(ALICE);
    vm.startPrank(ALICE);
    weth.approve(address(miniFL), 10 ether);
    miniFL.deposit(ALICE, wethPoolID, 10 ether);
    vm.stopPrank();

    // assert alice balance
    assertEq(_aliceWethBalanceBefore - weth.balanceOf(ALICE), 10 ether);

    // assert reward user info, both user info should be same
    _assertRewarderUserAmount(rewarder1, ALICE, wethPoolID, 10 ether);
    _assertRewarderUserAmount(rewarder2, ALICE, wethPoolID, 10 ether);
  }

  function testCorrectness_WhenDepositDebtToken_RewarderUserInfoShouldBeCorrect() external {
    uint256 _bobDebtTokenBalanceBefore = debtToken1.balanceOf(BOB);

    vm.startPrank(BOB);
    debtToken1.approve(address(miniFL), 10 ether);
    miniFL.deposit(BOB, debtTokenPoolID, 10 ether);
    vm.stopPrank();

    // assert bob balance
    assertEq(_bobDebtTokenBalanceBefore - debtToken1.balanceOf(BOB), 10 ether);

    // assert reward user info
    _assertRewarderUserAmount(rewarder1, BOB, debtTokenPoolID, 10 ether);
    // rewarder2 is not register in this pool then user amount should be 0
    _assertRewarderUserAmount(rewarder2, BOB, debtTokenPoolID, 0 ether);
  }

  function _assertRewarderUserAmount(
    Rewarder _rewarder,
    address _user,
    uint256 _pid,
    uint256 _expectedAmount
  ) internal {
    (uint256 _amount, ) = _rewarder.userInfo(_pid, _user);
    assertEq(_amount, _expectedAmount);
  }
}
