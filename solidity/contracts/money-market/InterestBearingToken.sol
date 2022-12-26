// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// bases
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// interfaces
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IViewFacet } from "./interfaces/IViewFacet.sol";

// libs
import { LibShareUtil } from "./libraries/LibShareUtil.sol";

contract InterestBearingToken is ERC20, IERC4626, Ownable, Initializable {
  address private _asset;
  IViewFacet private _viewFacet;
  uint8 private _decimals;

  constructor() ERC20("", "") {}

  /// @dev owner_ should be MoneyMarketDiamond
  function initialize(address asset_, address owner_) external initializer {
    _asset = asset_;
    _decimals = IERC20Metadata(_asset).decimals();
    _viewFacet = IViewFacet(owner_);
    _transferOwnership(owner_);
  }

  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external onlyOwner {
    _burn(from, amount);
  }

  /// -----------------------------------------------------------------------
  /// ERC4626 deposit/withdrawal logic
  /// -----------------------------------------------------------------------

  /**
   * @dev This method should be only called by LendFacet.deposit.
   *
   * actual deposit logic including token transfer is implemented in LendFacet,
   * which calls this method on deposit.
   */
  function deposit(uint256 assets, address receiver) external override onlyOwner returns (uint256 shares) {
    shares = convertToShares(assets);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /**
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 mint-like functionality
   */
  function mint(uint256 shares, address receiver) external override onlyOwner returns (uint256 assets) {}

  /**
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 withdraw-like functionality
   */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) external override onlyOwner returns (uint256 shares) {}

  /**
   * @dev This method should be only called by LendFacet.withdraw.
   *
   * actual withdrawal logic including token transfer is implemented in LendFacet,
   * which calls this method on withdraw.
   */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  ) external override returns (uint256 assets) {
    assets = convertToAssets(shares);
    emit Withdraw(msg.sender, receiver, owner, assets, shares);
  }

  /// -----------------------------------------------------------------------
  /// ERC4626 accounting logic
  /// -----------------------------------------------------------------------

  function asset() external view override returns (address) {
    return _asset;
  }

  function totalAssets() external view override returns (uint256) {
    return _viewFacet.getTotalToken(_asset);
  }

  function convertToShares(uint256 assets) public view override returns (uint256) {
    return _viewFacet.getIbShareFromUnderlyingAmount(_asset, assets);
  }

  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    return LibShareUtil.shareToValue(shares, _viewFacet.getTotalToken(_asset), totalSupply());
  }

  function previewDeposit(uint256 assets) external view override returns (uint256 shares) {
    return convertToShares(assets);
  }

  /**
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 mint-like functionality.
   */
  function previewMint(uint256 shares) external view override returns (uint256 assets) {}

  /**
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 withdraw-like functionality.
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
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 mint-like functionality.
   */
  function maxMint(address) external pure override returns (uint256 maxShares) {}

  /**
   * @notice intentionally left unimplemented since LendFacet doesn't have ERC4626 withdraw-like functionality.
   */
  function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {}

  /**
   * @notice intentionally left unimplemented since we don't know how many subAccount an address have,
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
