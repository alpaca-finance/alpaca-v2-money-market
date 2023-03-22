// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { InterestBearingTokenBaseTest, console } from "./InterestBearingTokenBaseTest.sol";

// contracts
import { InterestBearingToken } from "../../../contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IAdminFacet } from "../../../contracts/money-market/interfaces/IAdminFacet.sol";

// libs
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract InterestBearingToken_TransferTest is InterestBearingTokenBaseTest {
  using SafeERC20 for InterestBearingToken;

  InterestBearingToken internal ibToken;

  function setUp() public override {
    super.setUp();

    ibToken = deployInterestBearingToken(address(weth));

    vm.prank(moneyMarketDiamond);
    ibToken.onDeposit(BOB, 0, 1 ether);

    vm.prank(BOB);
    ibToken.approve(address(this), type(uint256).max);
  }

  function testCorrectness_WhenTransferToOther() external {
    vm.startPrank(BOB);
    ibToken.transfer(ALICE, 0.1 ether);
    ibToken.safeTransfer(ALICE, 0.1 ether);
    vm.stopPrank();

    ibToken.transferFrom(BOB, ALICE, 0.1 ether);
    ibToken.safeTransferFrom(BOB, ALICE, 0.1 ether);

    assertEq(ibToken.balanceOf(ALICE), 0.4 ether);
    assertEq(ibToken.balanceOf(BOB), 0.6 ether);
  }

  function testRevert_WhenSelfTransferWithTransfer() external {
    vm.prank(BOB);
    vm.expectRevert(InterestBearingToken.InterestBearingToken_InvalidDestination.selector);
    ibToken.transfer(BOB, 1 ether);

    assertEq(ibToken.balanceOf(BOB), 1 ether);
  }

  function testRevert_WhenSelfTransferWithTransferFrom() external {
    vm.expectRevert(InterestBearingToken.InterestBearingToken_InvalidDestination.selector);
    ibToken.transferFrom(BOB, BOB, 1 ether);

    assertEq(ibToken.balanceOf(BOB), 1 ether);
  }

  function testRevert_WhenTransferToIbTokenContract() external {
    vm.expectRevert(InterestBearingToken.InterestBearingToken_InvalidDestination.selector);
    ibToken.transferFrom(BOB, address(ibToken), 1 ether);

    vm.prank(BOB);
    vm.expectRevert(InterestBearingToken.InterestBearingToken_InvalidDestination.selector);
    ibToken.transfer(address(ibToken), 1 ether);
  }

  /**
   * @dev Have to use testFail because `safeTransfer` revert twice and
   * `vm.expectRevert()` can catch only 1 revert so another revert will cause test to fail.
   *
   * First revert by low-level call to `InterestBearingToken.transfer` by `safeTransfer`
   * with `InterestBearingToken_InvalidDestination` custom error.
   *
   * Second revert by safeTransfer itself from internal function `_callOptionalReturn`
   * with "SafeERC20: ERC20 operation did not succeed" error message.
   *
   * For more explaination, see docs in gotcha section
   * https://book.getfoundry.sh/cheatcodes/expect-revert?highlight=expectRevert#expectrevert
   */
  function testFail_WhenSelfTransferWithSafeTransfer() external {
    vm.prank(BOB);
    ibToken.safeTransfer(BOB, 1 ether);
  }

  /// @dev same as above
  function testFail_WhenSelfTransferWithSafeTransferFrom() external {
    ibToken.safeTransferFrom(BOB, BOB, 1 ether);
  }

  function testRevert_WhenTransferToZeroAddress() external {
    vm.prank(BOB);
    vm.expectRevert("ERC20: transfer to the zero address");
    ibToken.transfer(address(0), 1 ether);

    vm.expectRevert("ERC20: transfer to the zero address");
    ibToken.transferFrom(BOB, address(0), 1 ether);
  }
}
