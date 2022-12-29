// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { MoneyMarket_BaseTest, MockERC20, console } from "./MoneyMarket_BaseTest.t.sol";

// interfaces
import { INonCollatBorrowFacet, LibDoublyLinkedList } from "../../contracts/money-market/facets/NonCollatBorrowFacet.sol";
import { IBorrowFacet } from "../../contracts/money-market/facets/BorrowFacet.sol";
import { IAdminFacet } from "../../contracts/money-market/facets/AdminFacet.sol";
import { TripleSlopeModel6, IInterestRateModel } from "../../contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "../../contracts/money-market/interest-models/TripleSlopeModel7.sol";

// libs
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

contract MoneyMarket_NonCollatBorrow_BorrowTest is MoneyMarket_BaseTest {
  MockERC20 mockToken;

  function setUp() public override {
    super.setUp();

    mockToken = deployMockErc20("Mock token", "MOCK", 18);
    mockToken.mint(ALICE, 1000 ether);

    adminFacet.setNonCollatBorrower(ALICE, true);
    adminFacet.setNonCollatBorrower(BOB, true);

    vm.startPrank(ALICE);
    lendFacet.deposit(address(weth), 50 ether);
    lendFacet.deposit(address(usdc), 20 ether);
    lendFacet.deposit(address(btc), 20 ether);
    lendFacet.deposit(address(cake), 20 ether);
    lendFacet.deposit(address(isolateToken), 20 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowTokenFromMM_ShouldTransferTokenToUser() external {
    uint256 _borrowAmount = 10 ether;

    // BOB Borrow _borrowAmount
    vm.startPrank(BOB);
    uint256 _bobBalanceBefore = weth.balanceOf(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _bobBalanceAfter = weth.balanceOf(BOB);

    uint256 _bobDebtAmount = viewFacet.getNonCollatAccountDebt(BOB, address(weth));

    assertEq(_bobBalanceAfter - _bobBalanceBefore, _borrowAmount);
    assertEq(_bobDebtAmount, _borrowAmount);

    // ALICE Borrow _borrowAmount
    vm.startPrank(ALICE);
    uint256 _aliceBalanceBefore = weth.balanceOf(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _borrowAmount);
    vm.stopPrank();

    uint256 _aliceBalanceAfter = weth.balanceOf(ALICE);

    uint256 _aliceDebtAmount = viewFacet.getNonCollatAccountDebt(ALICE, address(weth));

    assertEq(_aliceBalanceAfter - _aliceBalanceBefore, _borrowAmount);
    assertEq(_aliceDebtAmount, _borrowAmount);

    // total debt should equal sum of alice's and bob's debt
    uint256 _totalDebtAmount = viewFacet.getNonCollatTokenDebt(address(weth));

    assertEq(_totalDebtAmount, _borrowAmount * 2);
    assertEq(_bobDebtAmount, _aliceDebtAmount);
  }

  function testRevert_WhenUserNonCollatBorrowTooMuchTokePerSubAccount() external {
    vm.startPrank(BOB);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 1 ether);
    nonCollatBorrowFacet.nonCollatBorrow(address(btc), 1 ether);
    nonCollatBorrowFacet.nonCollatBorrow(address(usdc), 1 ether);

    // now maximum is 3 token per account, when try borrow 4th token should revert
    vm.expectRevert(abi.encodeWithSelector(LibMoneyMarket01.LibMoneyMarket01_NumberOfTokenExceedLimit.selector));
    nonCollatBorrowFacet.nonCollatBorrow(address(cake), 1 ether);
    vm.stopPrank();
  }

  function testRevert_WhenUserBorrowNonAvailableToken_ShouldRevert() external {
    uint256 _borrowAmount = 10 ether;
    vm.startPrank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_InvalidToken.selector, address(mockToken))
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(mockToken), _borrowAmount);
    vm.stopPrank();
  }

  function testCorrectness_WhenUserBorrowMultipleTokens_ListShouldUpdate() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowAmount2 = 20 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getNonCollatAccountDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    // list will be add at the front of linkList
    nonCollatBorrowFacet.nonCollatBorrow(address(usdc), _aliceBorrowAmount2);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getNonCollatAccountDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    aliceDebtShares = viewFacet.getNonCollatAccountDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 2);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount2);
    assertEq(aliceDebtShares[1].amount, _aliceBorrowAmount * 2, "updated weth");

    uint256 _totalwethDebtAmount = viewFacet.getNonCollatTokenDebt(address(weth));

    assertEq(_totalwethDebtAmount, _aliceBorrowAmount * 2);
  }

  function testRevert_WhenUserBorrowMoreThanAvailable_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 30 ether;

    vm.startPrank(ALICE);

    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    LibDoublyLinkedList.Node[] memory aliceDebtShares = viewFacet.getNonCollatAccountDebtValues(ALICE);

    assertEq(aliceDebtShares.length, 1);
    assertEq(aliceDebtShares[0].amount, _aliceBorrowAmount);

    vm.startPrank(ALICE);

    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_NotEnoughToken.selector, _aliceBorrowAmount * 2)
    );

    // this should reverts as their is only 50 weth but alice try to borrow 60 (20 + (20*2))
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount * 2);
    vm.stopPrank();
  }

  function testRevert_WhenUserIsNotWhitelisted_ShouldRevert() external {
    vm.startPrank(CAT);

    vm.expectRevert(abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_Unauthorized.selector));
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 10 ether);
    vm.stopPrank();
  }

  function testCorrectness_WhenMultipleUserBorrowTokens_MMShouldTransferCorrectIbTokenAmount() external {
    uint256 _bobDepositAmount = 10 ether;
    uint256 _aliceBorrowAmount = 10 ether;

    vm.startPrank(ALICE);
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    lendFacet.deposit(address(weth), _bobDepositAmount);

    vm.stopPrank();

    assertEq(ibWeth.balanceOf(BOB), 10 ether);
  }

  function testRevert_WhenProtocolBorrowMoreThanLimitPower_ShouldRevert() external {
    uint256 _aliceBorrowAmount = 10 ether;
    uint256 _aliceBorrowLimit = 10 ether;

    uint256 _expectBorrowingPower = (_aliceBorrowAmount * 10000) / 9000;

    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](0);
    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](1);
    _protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: ALICE,
      tokenBorrowLimit: _tokenBorrowLimitInputs,
      borrowLimitUSDValue: _aliceBorrowLimit
    });

    adminFacet.setProtocolConfigs(_protocolConfigInputs);

    vm.prank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(
        INonCollatBorrowFacet.NonCollatBorrowFacet_BorrowingValueTooHigh.selector,
        _aliceBorrowAmount,
        0,
        _expectBorrowingPower
      )
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
  }

  function testRevert_WhenProtocolBorrowMoreThanTokenGlobalLimit_ShouldRevert() external {
    uint256 _wethGlobalLimit = 10 ether;
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: _wethGlobalLimit,
      maxCollateral: 100 ether
    });
    adminFacet.setTokenConfigs(_inputs);

    uint256 _aliceBorrowAmount = _wethGlobalLimit + 1;
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_ExceedBorrowLimit.selector));
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);
  }

  function testRevert_WhenUserBorrowUpToTokenGlobalLimit_ThenProtocolBorrowSameToken_ShouldRevert() external {
    uint256 _wethGlobalLimit = 10 ether;
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](1);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: _wethGlobalLimit,
      maxCollateral: 100 ether
    });
    adminFacet.setTokenConfigs(_inputs);

    // Over-collat borrow
    // BOB borrow weth upto Global limit
    vm.startPrank(BOB);
    collateralFacet.addCollateral(BOB, subAccount0, address(weth), _wethGlobalLimit * 2);
    borrowFacet.borrow(subAccount0, address(weth), _wethGlobalLimit);
    vm.stopPrank();

    // Non-collat borrow
    vm.prank(ALICE);
    vm.expectRevert(abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_ExceedBorrowLimit.selector));
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), 1);
  }

  function testRevert_WhenProtocolBorrowMoreThanTokenAccountLimit_ShouldRevert() external {
    uint256 _aliceWethAccountLimit = 5 ether;
    uint256 _bobWethAccountLimit = 4 ether;

    IAdminFacet.TokenBorrowLimitInput[] memory _aliceTokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](
      1
    );
    _aliceTokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(weth),
      maxTokenBorrow: _aliceWethAccountLimit
    });

    IAdminFacet.TokenBorrowLimitInput[] memory _bobTokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](1);
    _bobTokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(weth),
      maxTokenBorrow: _bobWethAccountLimit
    });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](2);
    _protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: ALICE,
      tokenBorrowLimit: _aliceTokenBorrowLimitInputs,
      borrowLimitUSDValue: type(uint256).max
    });

    _protocolConfigInputs[1] = IAdminFacet.ProtocolConfigInput({
      account: BOB,
      tokenBorrowLimit: _bobTokenBorrowLimitInputs,
      borrowLimitUSDValue: type(uint256).max
    });

    adminFacet.setProtocolConfigs(_protocolConfigInputs);

    uint256 _aliceBorrowAmount = _aliceWethAccountLimit + 1;
    uint256 _bobBorrowAmount = _bobWethAccountLimit + 1;
    vm.prank(ALICE);
    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_ExceedAccountBorrowLimit.selector)
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _aliceBorrowAmount);

    vm.prank(BOB);
    vm.expectRevert(
      abi.encodeWithSelector(INonCollatBorrowFacet.NonCollatBorrowFacet_ExceedAccountBorrowLimit.selector)
    );
    nonCollatBorrowFacet.nonCollatBorrow(address(weth), _bobBorrowAmount);
  }
}
