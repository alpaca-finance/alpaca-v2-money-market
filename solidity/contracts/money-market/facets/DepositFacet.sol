// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// libs
import { LibMoneyMarket01 } from "../libraries/LibMoneyMarket01.sol";
import { LibShareUtil } from "../libraries/LibShareUtil.sol";

// interfaces
import { IDepositFacet } from "../interfaces/IDepositFacet.sol";
import { IIbToken } from "../interfaces/IIbToken.sol";

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
    LibMoneyMarket01.MoneyMarketDiamondStorage
      storage moneyMarketDs = LibMoneyMarket01.moneyMarketDiamondStorage();

    address _ibToken = moneyMarketDs.tokenToIbTokens[_token];

    if (_ibToken == address(0)) {
      revert DepositFacet_InvalidToken(_token);
    }
    uint256 _totalSupply = IIbToken(_ibToken).totalSupply();
    uint256 _totalToken = ERC20(_token).balanceOf(address(this));

    // calculate _shareToMint to mint before transfer token to MM
    uint256 _shareToMint = LibShareUtil.valueToShare(
      _totalSupply,
      _amount,
      _totalToken
    );

    ERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IIbToken(_ibToken).mint(msg.sender, _shareToMint);

    emit LogDeposit(msg.sender, _token, _ibToken, _amount, _shareToMint);
  }
}
