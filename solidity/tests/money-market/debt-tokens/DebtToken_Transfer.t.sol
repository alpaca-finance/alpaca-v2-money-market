// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";

// contracts
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

// interfaces
import { IAdminFacet, LibMoneyMarket01 } from "../../../contracts/money-market/facets/AdminFacet.sol";

// libs
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DebtToken_TransferTest is MoneyMarket_BaseTest {
  using SafeERC20 for DebtToken;

  DebtToken internal debtToken;

  function setUp() public override {
    super.setUp();

    debtToken = new DebtToken();
    debtToken.initialize(address(weth), moneyMarketDiamond);

    vm.startPrank(moneyMarketDiamond);
    address[] memory _okHolders = new address[](1);
    _okHolders[0] = moneyMarketDiamond;

    debtToken.setOkHolders(_okHolders, true);
    debtToken.mint(moneyMarketDiamond, 1 ether);
    debtToken.approve(moneyMarketDiamond, 1 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenTransferToOther() external {
    vm.startPrank(moneyMarketDiamond);
    debtToken.transfer(ALICE, 0.1 ether);
    debtToken.safeTransfer(ALICE, 0.1 ether);

    debtToken.transferFrom(moneyMarketDiamond, ALICE, 0.1 ether);
    debtToken.safeTransferFrom(moneyMarketDiamond, ALICE, 0.1 ether);
    vm.stopPrank();

    assertEq(debtToken.balanceOf(ALICE), 0.4 ether);
    assertEq(debtToken.balanceOf(moneyMarketDiamond), 0.6 ether);
  }

  function testRevert_WhenNonOkHolderTransfer() external {
    vm.startPrank(ALICE);
    vm.expectRevert(DebtToken.DebtToken_UnApprovedHolder.selector);
    debtToken.transfer(ALICE, 0.1 ether);

    vm.expectRevert(DebtToken.DebtToken_UnApprovedHolder.selector);
    debtToken.transferFrom(moneyMarketDiamond, ALICE, 0.1 ether);
    vm.stopPrank();

    assertEq(debtToken.balanceOf(moneyMarketDiamond), 1 ether);
  }

  function testRevert_WhenSelfTransfer() external {
    vm.startPrank(moneyMarketDiamond);
    vm.expectRevert(DebtToken.DebtToken_NoSelfTransfer.selector);
    debtToken.transfer(moneyMarketDiamond, 1 ether);

    vm.expectRevert(DebtToken.DebtToken_NoSelfTransfer.selector);
    debtToken.transferFrom(moneyMarketDiamond, moneyMarketDiamond, 1 ether);
    vm.stopPrank();

    assertEq(debtToken.balanceOf(moneyMarketDiamond), 1 ether);
  }

  /**
   * @dev Have to use testFail because `safeTransfer` revert twice and
   * `vm.expectRevert()` can catch only 1 revert so another revert will cause test to fail.
   *
   * First revert by low-level call to `DebtToken.transfer` by `safeTransfer`
   * with `DebtToken_NoSelfTransfer` custom error.
   *
   * Second revert by safeTransfer itself from internal function `_callOptionalReturn`
   * with "SafeERC20: ERC20 operation did not succeed" error message.
   *
   * For more explaination, see docs in gotcha section
   * https://book.getfoundry.sh/cheatcodes/expect-revert?highlight=expectRevert#expectrevert
   */
  function testFail_WhenSelfTransferWithSafeTransfer() external {
    debtToken.safeTransfer(ALICE, 1 ether);
  }

  /// @dev same as above
  function testFail_WhenSelfTransferWithSafeTransferFrom() external {
    debtToken.safeTransferFrom(moneyMarketDiamond, ALICE, 1 ether);
  }

  function testRevert_WhenTransferToZeroAddress() external {
    vm.startPrank(moneyMarketDiamond);
    vm.expectRevert("ERC20: transfer to the zero address");
    debtToken.transfer(address(0), 1 ether);

    vm.expectRevert("ERC20: transfer to the zero address");
    debtToken.transferFrom(moneyMarketDiamond, address(0), 1 ether);
    vm.stopPrank();
  }
}
