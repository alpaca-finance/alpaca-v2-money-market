// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { LibMoneyMarketStorage } from "../libraries/LibMoneyMarketStorage.sol";

import { IDepositFacet } from "../interfaces/IDepositFacet.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DepositFacet is IDepositFacet {
  using SafeERC20 for ERC20;

  event LogDeposit(
    address indexed _user,
    address _token,
    address _ibToken,
    uint256 _amountIn,
    uint256 _amountOut
  );

  function deposit(address _token, uint256 _amount) external {
    LibMoneyMarketStorage.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarketStorage.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken == address(0)) {
      revert DepositFacet_InvalidToken(_token);
    }

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IIbToken(_ibToken).mint(msg.sender, _amount);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _amount);
  }
}
