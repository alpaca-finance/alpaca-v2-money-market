// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// ---- Interfaces ---- //
// path reader
import { IPancakeSwapRouterV3 } from "../money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

interface ISmartTreasury {
  error SmartTreasury_AmountTooLow();
  error SmartTreasury_NoBalance();
  error SmartTreasury_PathConfigNotFound();
  error SmartTreasury_Unauthorized();

  // call to auto split target token to each destination
  function distribute(address calldata _tokens) external;

  function setAllocs(
    uint256 _revenueAlloc,
    uint256 _devAlloc,
    uint256 _burnAlloc
  ) external;

  function setWhitelistedCallers(address[] calldata _callers, bool _allow) external;
}

// whitelist (can be both Eoa and contract)
// this contract hold treasury
contract SmartTreasury is OwnableUpgradeable, ISmartTreasury {
  using LibSafeToken for IERC20;

  address public revenueTreasury;
  address public devTreasury;
  address public burnTreasury;

  mapping(address => bool) public whitelistedCallers;

  uint16 public revenueAlloc;
  uint16 public devAlloc;
  uint16 public burnAlloc;

  address internal constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
  IPancakeSwapRouterV3 internal constant PCS_V3_ROUTER = IPancakeSwapRouterV3(address(1));
  // IUniSwapV3PathReader internal immutable pathReader;

  event LogDistribute(address _token, uint256 _amount);
  event LogSetWhitelistedCaller(address indexed _caller, bool _allow);
  event LogSetAllocs(uint256 _revenueAlloc, uint256 _devAlloc, uint256 _burnAlloc, uint256 totalAlloc);

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert SmartTreasury_Unauthorized();
    }
    _;
  }

  // target 1 address First portion is to swapped token to “BUSD” and send to RevenueTreasury from AF1.0
  // target 2 address Second portion is to transfer token to dev treasury address (0x08B5A95cb94f926a8B620E87eE92e675b35afc7E)
  // target 3 address Third portion is to transfer token to "buy back" and burn treasury address (address ?)

  constructor() {
    _disableInitializers();
  }

  function initialize() external initializer {
    OwnableUpgradeable.__Ownable_init();
  }

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

  function _distribute(address _token) internal {
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    (uint256 _revenueAmount, uint256 _devAmount, uint256 _burnAmount) = _splitPayment(_amount);

    bytes memory _path = pathReader.paths(_token, BUSD);
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
    returns (
      uint256 _revenueAmount,
      uint256 _devAmount,
      uint256 _burnAmount
    )
  {
    if (_amount <= LibConstant.MAX_BPS) revert SmartTreasury_AmountTooLow();
    _devAmount = (_amount * devAlloc) / LibConstant.MAX_BPS;
    _burnAmount = (_amount * burnAlloc) / LibConstant.MAX_BPS;
    unchecked {
      _revenueAmount = _amount - _devAmount - _burnAmount;
    }
  }

  uint256 public totalAlloc;

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
}
