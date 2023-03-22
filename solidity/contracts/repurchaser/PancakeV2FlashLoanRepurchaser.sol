// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "solidity/contracts/interfaces/IERC20.sol";
import { IMoneyMarket } from "solidity/contracts/money-market/interfaces/IMoneyMarket.sol";
import { IMoneyMarketAccountManager } from "solidity/contracts/interfaces/IMoneyMarketAccountManager.sol";
import { IPancakeCallee } from "solidity/contracts/repurchaser/interfaces/IPancakeCallee.sol";
import { IPancakeRouter01 } from "solidity/contracts/repurchaser/interfaces/IPancakeRouter01.sol";

contract PancakeV2FlashLoanRepurchaser is IPancakeCallee {
  error PancakeV2FlashLoanRepurchaser_Unauthorized();

  // TODO: change to constant when deploy
  address public immutable owner;
  IMoneyMarket public immutable moneyMarketDiamond;
  IMoneyMarketAccountManager public immutable accountManager;
  IPancakeRouter01 public immutable pancakeRouter;

  constructor(
    address _moneyMarketDiamond,
    address _accountManager,
    address _pancakeRouter
  ) {
    owner = msg.sender;
    moneyMarketDiamond = IMoneyMarket(_moneyMarketDiamond);
    accountManager = IMoneyMarketAccountManager(_accountManager);
    pancakeRouter = IPancakeRouter01(_pancakeRouter);
  }

  function withdrawToken(address _token) external {
    if (msg.sender != owner) revert PancakeV2FlashLoanRepurchaser_Unauthorized();
    IERC20(_token).transfer(owner, IERC20(_token).balanceOf(address(this)));
  }

  /// @param sender is original caller of pair `swap` function
  //                while `msg.sender` is pair contract
  function pancakeCall(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external override {
    // only allow owner to initiate flashswap
    if (sender != owner) revert PancakeV2FlashLoanRepurchaser_Unauthorized();

    (
      address _account,
      uint256 _subAccountId,
      address _debtToken,
      address _underlyingOfCollatToken, // underlying of ib collat
      address _collatToken, // ib collat, pass from outside to save gas
      uint256 _desiredRepayAmount,
      // skip path validation to save gas since it would revert anyway if path is wrong
      // expect that path[0] = _underlyingOfCollatToken, path[len - 1] = _debtToken
      address[] memory _path
    ) = abi.decode(data, (address, uint256, address, address, address, uint256, address[]));

    // we swap from underlyingOfCollat (tokenIn) to debt (tokenOut)
    // so we use `getAmountsIn` to find amount to repay flashloan
    uint256[] memory _amounts = pancakeRouter.getAmountsIn(
      // `_debtToken < _underlyingOfCollatToken` means `_debtToken` is token0
      _debtToken < _underlyingOfCollatToken ? amount0 : amount1,
      _path
    );
    uint256 _amountRepayFlashloan = _amounts[0];

    uint256 _underlyingBefore = IERC20(_underlyingOfCollatToken).balanceOf(address(this));

    _repurchaseIbCollat(_account, _subAccountId, _debtToken, _collatToken, _desiredRepayAmount);

    // TODO: profit threshold?
    // revert if unprofitable
    if (IERC20(_underlyingOfCollatToken).balanceOf(address(this)) - _underlyingBefore - _amountRepayFlashloan == 0)
      revert();

    // repay flashloan
    IERC20(_underlyingOfCollatToken).transfer(msg.sender, _amountRepayFlashloan);
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
    IERC20(_debtToken).approve(address(moneyMarketDiamond), type(uint256).max);
    uint256 _collatTokenReceived = moneyMarketDiamond.repurchase(
      _account,
      _subAccountId,
      _debtToken,
      _collatToken,
      _desiredRepayAmount
    );
    IERC20(_debtToken).approve(address(moneyMarketDiamond), 0);

    // fine to approve exact amount because withdraw will spend it all
    IERC20(_collatToken).approve(address(accountManager), _collatTokenReceived);
    accountManager.withdraw(_collatToken, _collatTokenReceived);
  }
}
