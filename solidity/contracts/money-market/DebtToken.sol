// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// ---- External Libraries ---- //
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// ---- Interfaces ---- //
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IDebtToken } from "./interfaces/IDebtToken.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";

contract DebtToken is IDebtToken, ERC20, Ownable, Initializable {
  address private _asset;
  IMoneyMarket private _moneyMarket;
  uint8 private _decimals;

  mapping(address => bool) public okHolders;

  constructor() ERC20("", "") {}

  function initialize(address asset_, address moneyMarket_) external initializer {
    _moneyMarket = IMoneyMarket(moneyMarket_);
    // sanity check
    _moneyMarket.getTotalToken(asset_);

    _asset = asset_;
    _decimals = IERC20Metadata(asset_).decimals();
    _transferOwnership(moneyMarket_);
  }

  function moneyMarket() external view returns (address) {
    return address(_moneyMarket);
  }

  function setOkHolders(address[] calldata _okHolders, bool _isOk) public override onlyOwner {
    uint256 _length = _okHolders.length;
    for (uint256 _idx; _idx < _length; ) {
      okHolders[_okHolders[_idx]] = _isOk;
      unchecked {
        ++_idx;
      }
    }
  }

  function mint(address to, uint256 amount) public override onlyOwner {
    if (!okHolders[to]) {
      revert DebtToken_UnApprovedHolder();
    }
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) public override onlyOwner {
    if (!okHolders[from]) {
      revert DebtToken_UnApprovedHolder();
    }
    _burn(from, amount);
  }

  function name() public view override returns (string memory) {
    return string.concat("debt", IERC20Metadata(_asset).symbol());
  }

  function symbol() public view override returns (string memory) {
    return string.concat("debt", IERC20Metadata(_asset).symbol());
  }

  function decimals() public view override(ERC20, IDebtToken) returns (uint8) {
    return _decimals;
  }

  function transfer(address to, uint256 amount) public override returns (bool) {
    if (!(okHolders[msg.sender] && okHolders[to])) {
      revert DebtToken_UnApprovedHolder();
    }
    if (msg.sender == to) {
      revert DebtToken_NoSelfTransfer();
    }
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public override returns (bool) {
    if (!(okHolders[msg.sender] && okHolders[to])) {
      revert DebtToken_UnApprovedHolder();
    }
    if (from == to) {
      revert DebtToken_NoSelfTransfer();
    }
    _spendAllowance(from, _msgSender(), amount);
    _transfer(from, to, amount);
    return true;
  }
}
