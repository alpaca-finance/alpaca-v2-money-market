// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IPancakeCallee } from "solidity/contracts/repurchaser/interfaces/IPancakeCallee.sol";
import { IPancakeRouter01 } from "solidity/contracts/repurchaser/interfaces/IPancakeRouter01.sol";

import { LibSafeToken } from "./libraries/LibSafeToken.sol";

contract PancakeV2FlashLoanRepurchaser is IPancakeCallee {
  using LibSafeToken for IERC20;

  error PancakeV2FlashLoanRepurchaser_Unauthorized();

  // TODO: change to constant when deploy
  address public immutable owner;
  IMoneyMarket public immutable moneyMarketDiamond;
  IMoneyMarketAccountManager public immutable accountManager;
  IPancakeRouter01 public immutable pancakeRouter;

  constructor(
    address _owner,
    address _moneyMarketDiamond,
    address _accountManager,
    address _pancakeRouter
  ) {
    owner = _owner;
    moneyMarketDiamond = IMoneyMarket(_moneyMarketDiamond);
    accountManager = IMoneyMarketAccountManager(_accountManager);
    pancakeRouter = IPancakeRouter01(_pancakeRouter);
  }

  function withdrawToken(address _token) external {
    if (msg.sender != owner) revert PancakeV2FlashLoanRepurchaser_Unauthorized();
    IERC20(_token).safeTransfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  /// @param sender is original caller of pair `swap` function. while `msg.sender` is pair contract
  /// @param amount0 amount of token0 sent from pair
  /// @param amount1 amount of token1 sent from pair
  /// @param data extra data for callback
  function pancakeCall(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external override {
    // only allow owner to initiate flashswap
    if (sender != owner) revert PancakeV2FlashLoanRepurchaser_Unauthorized();
    // intentionally skip pair correctness check because we trust caller aka owner

    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount
    ) = abi.decode(data, (address, uint256, address, address, address, uint256));

    // currently support only single-hop
    address[] memory _path = new address[](2);
    _path[0] = _underlyingOfCollatToken;
    _path[1] = _debtToken;
    // we swap from underlyingOfCollat (tokenIn) to debt (tokenOut)
    // so we use `getAmountsIn` to find amount to repay flashloan
    uint256[] memory _amounts = pancakeRouter.getAmountsIn(
      // `_debtToken < _underlyingOfCollatToken` means `_debtToken` is token0
      _debtToken < _underlyingOfCollatToken ? amount0 : amount1,
      _path
    );
    uint256 _amountRepayFlashloan = _amounts[0];

    _repurchaseIbCollat(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // repay flashloan. will revert underflow if unprofitable
    IERC20(_underlyingOfCollatToken).safeTransfer(msg.sender, _amountRepayFlashloan);
    // remaining profit after repay flashloan will remain in this contract until we call `withdrawToken`
  }

  function _repurchaseIbCollat(
    address _account,
    uint256 _subAccountId,
    address _debtToken,
    address _collatToken,
    uint256 _desiredRepayAmount
  ) internal {
    // approve max and reset because we don't know exact repay amount
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), type(uint256).max);
    uint256 _collatTokenReceived = moneyMarketDiamond.repurchase(
      _account,
      _subAccountId,
      _debtToken,
      _collatToken,
      _desiredRepayAmount
    );
    IERC20(_debtToken).safeApprove(address(moneyMarketDiamond), 0);

    // fine to approve exact amount because withdraw will spend it all
    IERC20(_collatToken).safeApprove(address(accountManager), _collatTokenReceived);
    accountManager.withdraw(_collatToken, _collatTokenReceived);
  }
}
