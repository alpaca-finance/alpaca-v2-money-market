// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// ---- Interfaces ---- //
import { IUniSwapV3PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV3PathReader.sol";
import { IPancakeSwapRouterV3 } from "../money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "../money-market/interfaces/IERC20.sol";
import { ISmartTreasury } from "./ISmartTreasury.sol";

contract SmartTreasury is OwnableUpgradeable, ISmartTreasury {
  using LibSafeToken for IERC20;

  address public revenueTreasury;
  address public devTreasury;
  address public burnTreasury;
  address public revenueToken;

  mapping(address => bool) public whitelistedCallers;

  uint256 public revenueAlloc;
  uint256 public devAlloc;
  uint256 public burnAlloc;
  uint256 public totalAlloc;

  IPancakeSwapRouterV3 public PCS_V3_ROUTER;
  IUniSwapV3PathReader public pathReader;

  event LogDistribute(address _token, uint256 _amount);
  event LogSetAllocs(uint256 _revenueAlloc, uint256 _devAlloc, uint256 _burnAlloc, uint256 totalAlloc);
  event LogSetRevenueToken(address _revenueToken);
  event LogSetWhitelistedCaller(address indexed _caller, bool _allow);

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert SmartTreasury_Unauthorized();
    }
    _;
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(address _router, address _pathReader) external initializer {
    OwnableUpgradeable.__Ownable_init();
    PCS_V3_ROUTER = IPancakeSwapRouterV3(_router);
    pathReader = IUniSwapV3PathReader(_pathReader);
  }

  /// @notice Distribute the balance in this contract to each treasury
  /// @dev This function will be called by external.
  /// @param _tokens An array of tokens that want to distribute.
  function distribute(address[] calldata _tokens) external onlyWhitelisted {
    uint256 _length = _tokens.length;
    for (uint256 _i; _i < _length; ) {
      // should try catch?
      _distribute(_tokens[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set allocation points
  /// @param _revenueAlloc An allocation point for revenue treasury.
  /// @param _devAlloc An allocation point for dev treasury.
  /// @param _burnAlloc An allocation point for burn treasury.
  function setAllocs(
    uint256 _revenueAlloc,
    uint256 _devAlloc,
    uint256 _burnAlloc
  ) external onlyWhitelisted {
    totalAlloc = _revenueAlloc + _devAlloc + _burnAlloc;
    revenueAlloc = _revenueAlloc;
    devAlloc = _devAlloc;
    burnAlloc = _burnAlloc;

    emit LogSetAllocs(_revenueAlloc, _devAlloc, _burnAlloc, totalAlloc);
  }

  /// @notice Set revenue token
  /// @dev Revenue token used for swapping before transfer to revenue treasury.
  /// @param _revenueToken An address of destination token.
  function setRevenueToken(address _revenueToken) external onlyWhitelisted {
    revenueToken = _revenueToken;
    emit LogSetRevenueToken(_revenueToken);
  }

  /// @notice Set whitelisted callers
  /// @param _callers The addresses of the callers that are going to be whitelisted.
  /// @param _allow Whether to allow or disallow callers.
  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external onlyOwner {
    uint256 _length = _callers.length;
    for (uint256 _i; _i < _length; ) {
      whitelistedCallers[_callers[_i]] = _allow;
      emit LogSetWhitelistedCaller(_callers[_i], _allow);

      unchecked {
        ++_i;
      }
    }
  }

  function _distribute(address _token) internal {
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    (uint256 _revenueAmount, uint256 _devAmount, uint256 _burnAmount) = _splitPayment(_amount);

    bytes memory _path = pathReader.paths(_token, revenueToken);
    if (_path.length == 0) revert SmartTreasury_PathConfigNotFound();

    IPancakeSwapRouterV3.ExactInputParams memory params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: revenueTreasury,
      deadline: block.timestamp,
      amountIn: _revenueAmount,
      amountOutMinimum: 0
    });

    // Direct send to revenue treasury
    IERC20(_token).safeApprove(address(PCS_V3_ROUTER), _revenueAmount);
    PCS_V3_ROUTER.exactInput(params);

    IERC20(_token).safeTransfer(devTreasury, _devAmount);
    IERC20(_token).safeTransfer(burnTreasury, _burnAmount);

    emit LogDistribute(_token, _amount);
  }

  function _splitPayment(uint256 _amount)
    internal
    view
    returns (
      uint256 _revenueAmount,
      uint256 _devAmount,
      uint256 _burnAmount
    )
  {
    _devAmount = (_amount * devAlloc) / totalAlloc;
    _burnAmount = (_amount * burnAlloc) / totalAlloc;
    unchecked {
      _revenueAmount = _amount - _devAmount - _burnAmount;
    }
    if (_devAmount == 0 || _burnAmount == 0 || _revenueAmount == 0) revert SmartTreasury_AmountTooLow();
  }
}
