// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { InterestBearingTokenBaseTest, console } from "./InterestBearingTokenBaseTest.sol";

// contracts
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

contract InterestBearingToken_ERC4626Test is InterestBearingTokenBaseTest {
  InterestBearingToken internal ibToken;

  function setUp() public override {
    super.setUp();

    ibToken = deployInterestBearingToken(address(weth));
  }

  function testCorrectness_WhenCallImplementedGetterMethods_ShouldWork() external {
    // static stuff
    assertEq(ibToken.asset(), address(weth));
    assertEq(ibToken.maxDeposit(ALICE), type(uint256).max);
    assertEq(ibToken.name(), string.concat("Interest Bearing ", weth.symbol()));
    assertEq(ibToken.symbol(), string.concat("ib", weth.symbol()));
    assertEq(ibToken.decimals(), weth.decimals());

    uint256 _ibTokenDecimal = ibToken.decimals();

    // empty state
    assertEq(ibToken.totalAssets(), 0);
    assertEq(
      ibToken.convertToAssets(normalizeEther(1 ether, _ibTokenDecimal)),
      normalizeEther(1 ether, _ibTokenDecimal)
    );
    assertEq(
      ibToken.convertToShares(normalizeEther(1 ether, _ibTokenDecimal)),
      normalizeEther(1 ether, _ibTokenDecimal)
    );
    assertEq(
      ibToken.previewDeposit(normalizeEther(1 ether, _ibTokenDecimal)),
      ibToken.convertToShares(normalizeEther(1 ether, _ibTokenDecimal))
    );
    assertEq(
      ibToken.previewRedeem(normalizeEther(1 ether, _ibTokenDecimal)),
      ibToken.convertToAssets(normalizeEther(1 ether, _ibTokenDecimal))
    );

    // simulate deposit by deposit to diamond to increase reserves and call onDeposit to mint ibToken
    // need to do like this because ibWeth deployed by diamond is not the same as ibToken deployed in this test
    // 1 ibToken = 2 weth
    vm.prank(ALICE);
    accountManager.deposit(address(weth), normalizeEther(2 ether, _ibTokenDecimal));
    vm.prank(moneyMarketDiamond);
    ibToken.onDeposit(ALICE, 0, normalizeEther(1 ether, _ibTokenDecimal));

    // state after deposit
    assertEq(ibToken.totalAssets(), normalizeEther(2 ether, _ibTokenDecimal));
    assertEq(
      ibToken.convertToAssets(normalizeEther(1 ether, _ibTokenDecimal)),
      normalizeEther(2 ether, _ibTokenDecimal)
    );
    assertEq(
      ibToken.convertToShares(normalizeEther(1 ether, _ibTokenDecimal)),
      normalizeEther(0.5 ether, _ibTokenDecimal)
    );
    assertEq(
      ibToken.previewDeposit(normalizeEther(1 ether, _ibTokenDecimal)),
      ibToken.convertToShares(normalizeEther(1 ether, _ibTokenDecimal))
    );
    assertEq(
      ibToken.previewRedeem(normalizeEther(1 ether, _ibTokenDecimal)),
      ibToken.convertToAssets(normalizeEther(1 ether, _ibTokenDecimal))
    );
  }
}
