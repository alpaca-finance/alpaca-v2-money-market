// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

// bases
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// interfaces
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IMoneyMarket } from "./interfaces/IMoneyMarket.sol";

// libs
import { LibShareUtil } from "./libraries/LibShareUtil.sol";

import "solidity/tests/utils/console.sol";

contract InterestBearingToken is ERC20, IERC4626, Ownable, Initializable {
  address private _asset;
  IMoneyMarket private _moneyMarket;
  uint8 private _decimals;

  constructor() ERC20("", "") {}

  function initialize(address asset_, address moneyMarket_) external initializer {
    _moneyMarket = IMoneyMarket(moneyMarket_);
    // sanity check
    _moneyMarket.getTotalToken(asset_);

    _asset = asset_;
    _decimals = IERC20Metadata(_asset).decimals();
    _transferOwnership(moneyMarket_);
  }

  function moneyMarket() external view returns (address) {
    return address(_moneyMarket);
  }

  /**
   * @dev Hook for LendFacet to call when deposit.
   *
   * It emits `Deposit` event that is expected by ERC4626 standard when deposit / mint.
   */
  function onDeposit(
    address receiver,
    uint256 assets,
    uint256 shares
  ) external onlyOwner {
    _mint(receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @dev Hook for LendFacet to call when withdraw.
   *
   * It emits `Withdraw` event that is expected by ERC4626 standard when withdraw / redeem.
   */
  function onWithdraw(
    address owner,
    address receiver,
    uint256 assets,
    uint256 shares
  ) external onlyOwner {
    _burn(owner, shares);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /// -----------------------------------------------------------------------
  /// ERC4626 deposit/withdrawal logic
  /// -----------------------------------------------------------------------

  /**
   * @dev Intentionally left unimplemented since we don't allow users to deposit via ibToken.
   *
   * Actual deposit logic including token transfer is implemented in LendFacet.
   */
  function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {}

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 mint-like functionality
   */
  function mint(uint256 shares, address receiver) external override returns (uint256 assets) {}

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 withdraw-like functionality
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) external override returns (uint256 shares) {}

  /**
   * @dev Intentionally left unimplemented since we don't allow users to withdraw via ibToken.
   *
   * Actual withdrawal logic including token transfer is implemented in LendFacet.
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external override returns (uint256 assets) {}

  /// -----------------------------------------------------------------------
  /// ERC4626 accounting logic
  /// -----------------------------------------------------------------------

  function asset() external view override returns (address assetTokenAddress) {
    return _asset;
  }

  function totalAssets() external view override returns (uint256 totalManagedAssets) {
    return _moneyMarket.getTotalTokenWithPendingInterest(_asset);
  }

  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    return LibShareUtil.valueToShare(assets, totalSupply(), _moneyMarket.getTotalToken(_asset));
  }

  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    return LibShareUtil.shareToValue(shares, _moneyMarket.getTotalToken(_asset), totalSupply());
  }

  function previewDeposit(uint256 assets) external view override returns (uint256 shares) {
    return convertToShares(assets);
  }

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 mint-like functionality.
   */
  function previewMint(uint256 shares) external view override returns (uint256 assets) {}

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 withdraw-like functionality.
   */
  function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {}

  function previewRedeem(uint256 shares) external view override returns (uint256 assets) {
    return convertToAssets(shares);
  }

  /// -----------------------------------------------------------------------
  /// ERC4626 limit logic
  /// -----------------------------------------------------------------------

  function maxDeposit(address) external pure override returns (uint256 maxAssets) {
    return type(uint256).max;
  }

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 mint-like functionality.
   */
  function maxMint(address) external pure override returns (uint256 maxShares) {}

  /**
   * @dev Intentionally left unimplemented since we didn't implement ERC4626 withdraw-like functionality.
   */
  function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {}

  /**
   * @dev Intentionally left unimplemented since we don't know how many subAccount an address have,
   * so we can't find how much an address has borrowed.
   */
  function maxRedeem(address owner) external view override returns (uint256 maxShares) {}

  /// -----------------------------------------------------------------------
  /// ERC20 overrides
  /// -----------------------------------------------------------------------

  function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
    return string.concat("Interest Bearing ", IERC20Metadata(_asset).symbol());
  }

  function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
    return string.concat("ib", IERC20Metadata(_asset).symbol());
  }

  function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
    return _decimals;
  }
}
