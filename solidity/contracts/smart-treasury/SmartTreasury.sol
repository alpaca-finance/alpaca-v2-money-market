// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

// ---- Interfaces ---- //
import { IUniSwapV3PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV3PathReader.sol";
import { IPancakeSwapRouterV3 } from "../money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "../money-market/interfaces/IERC20.sol";
import { ISmartTreasury } from "../interfaces/ISmartTreasury.sol";
import { IOracleMedianizer } from "solidity/contracts/oracle/interfaces/IOracleMedianizer.sol";

contract SmartTreasury is OwnableUpgradeable, ISmartTreasury {
  using LibSafeToken for IERC20;

  event LogDistribute(address _token, uint256 _revenueAmount, uint256 _devAmount, uint256 _burnAmount);
  event LogSetAllocPoints(uint256 _revenueAllocPoint, uint256 _devAllocPoint, uint256 _burnAllocPoint);
  event LogSetRevenueToken(address _revenueToken);
  event LogSetWhitelistedCaller(address indexed _caller, bool _allow);
  event LogFailedDistribution(address _token, bytes _reason);
  event LogSetSlippageToleranceBps(uint256 _slippageToleranceBps);
  event LogSetTreasuryAddresses(address _revenueTreasury, address _devTreasury, address _burnTreasury);
  event LogWithdraw(address _to, address _token, uint256 _amount);

  address public constant USD = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  // TODO: revise to address, allo

  address public revenueTreasury;
  uint16 public revenueAllocPoint;

  address public devTreasury;
  uint16 public devAllocPoint;

  address public burnTreasury;
  uint16 public burnAllocPoint;

  address public revenueToken;

  IPancakeSwapRouterV3 public router;
  IUniSwapV3PathReader public pathReader;
  IOracleMedianizer public oracleMedianizer;

  mapping(address => bool) public whitelistedCallers;
  uint16 public slippageToleranceBps;

  modifier onlyWhitelisted() {
    if (!whitelistedCallers[msg.sender]) {
      revert SmartTreasury_Unauthorized();
    }
    _;
  }

  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _router,
    address _pathReader,
    address _oracleMedianizer
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    router = IPancakeSwapRouterV3(_router);
    pathReader = IUniSwapV3PathReader(_pathReader);
    oracleMedianizer = IOracleMedianizer(_oracleMedianizer);
  }

  /// @notice Distribute the balance in this contract to each treasury
  /// @dev This function will be called by external.
  /// @param _tokens An array of tokens that want to distribute.
  function distribute(address[] calldata _tokens) external onlyWhitelisted {
    uint256 _length = _tokens.length;
    for (uint256 _i; _i < _length; ) {
      _distribute(_tokens[_i]);
      unchecked {
        ++_i;
      }
    }
  }

  /// @notice Set allocation points
  /// @param _revenueAllocPoint revenue treasury allocation point
  /// @param _devAllocPoint dev treasury allocation point
  /// @param _burnAllocPoint burn treasury allocation point
  function setAllocPoints(
    uint16 _revenueAllocPoint,
    uint16 _devAllocPoint,
    uint16 _burnAllocPoint
  ) external onlyWhitelisted {
    if (
      _revenueAllocPoint > LibConstant.MAX_BPS ||
      _devAllocPoint > LibConstant.MAX_BPS ||
      _burnAllocPoint > LibConstant.MAX_BPS
    ) {
      revert SmartTreasury_InvalidAllocPoint();
    }

    revenueAllocPoint = _revenueAllocPoint;
    devAllocPoint = _devAllocPoint;
    burnAllocPoint = _burnAllocPoint;

    emit LogSetAllocPoints(_revenueAllocPoint, _devAllocPoint, _burnAllocPoint);
  }

  /// @notice Set revenue token
  /// @dev Revenue token used for swapping before transfer to revenue treasury.
  /// @param _revenueToken An address of destination token.
  function setRevenueToken(address _revenueToken) external onlyWhitelisted {
    IERC20(_revenueToken).decimals();

    revenueToken = _revenueToken;
    emit LogSetRevenueToken(_revenueToken);
  }

  /// @notice Set Slippage tolerance (bps)
  /// @param _slippageToleranceBps Amount of Slippage Tolerance (bps)
  function setSlippageToleranceBps(uint16 _slippageToleranceBps) external onlyWhitelisted {
    if (_slippageToleranceBps > LibConstant.MAX_BPS) {
      revert SmartTreasury_SlippageTolerance();
    }
    slippageToleranceBps = _slippageToleranceBps;
    emit LogSetSlippageToleranceBps(_slippageToleranceBps);
  }

  /// @notice Set treasury addresses
  /// @dev The destination addresses for distribution
  /// @param _revenueTreasury An address of revenue treasury
  /// @param _devTreasury An address of dev treasury
  /// @param _burnTreasury An address of burn treasury
  function setTreasuryAddresses(
    address _revenueTreasury,
    address _devTreasury,
    address _burnTreasury
  ) external onlyWhitelisted {
    if (_revenueTreasury == address(0) || _devTreasury == address(0) || _burnTreasury == address(0)) {
      revert SmartTreasury_InvalidAddress();
    }

    revenueTreasury = _revenueTreasury;
    devTreasury = _devTreasury;
    burnTreasury = _burnTreasury;

    emit LogSetTreasuryAddresses(_revenueTreasury, _devTreasury, _burnTreasury);
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

  function _getMinAmountOut(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn
  ) internal view returns (uint256 _minAmountOut) {
    (uint256 _tokenInPrice, ) = oracleMedianizer.getPrice(_tokenIn, USD);

    uint256 _minAmountOutUSD = (_amountIn * _tokenInPrice * (LibConstant.MAX_BPS - slippageToleranceBps)) /
      (10**IERC20(_tokenIn).decimals() * LibConstant.MAX_BPS);

    (uint256 _tokenOutPrice, ) = oracleMedianizer.getPrice(_tokenOut, USD);
    _minAmountOut = ((_minAmountOutUSD * (10**IERC20(_tokenOut).decimals())) / _tokenOutPrice);
  }

  function _distribute(address _token) internal {
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    (uint256 _revenueAmount, uint256 _devAmount, uint256 _burnAmount) = _allocate(_amount);

    if (_revenueAmount != 0) {
      if (_token == revenueToken) {
        IERC20(_token).safeTransfer(revenueTreasury, _revenueAmount);
      } else {
        bytes memory _path = pathReader.paths(_token, revenueToken);
        if (_path.length == 0) {
          revert SmartTreasury_PathConfigNotFound();
        }

        IPancakeSwapRouterV3.ExactInputParams memory params = IPancakeSwapRouterV3.ExactInputParams({
          path: _path,
          recipient: revenueTreasury,
          deadline: block.timestamp,
          amountIn: _revenueAmount,
          amountOutMinimum: _getMinAmountOut(_token, revenueToken, _revenueAmount)
        });

        // Swap and send to revenue treasury
        IERC20(_token).safeApprove(address(router), _revenueAmount);
        try router.exactInput(params) {} catch (bytes memory _reason) {
          emit LogFailedDistribution(_token, _reason);
          return;
        }
      }
    }

    if (_devAmount != 0) {
      IERC20(_token).safeTransfer(devTreasury, _devAmount);
    }

    if (_burnAmount != 0) {
      IERC20(_token).safeTransfer(burnTreasury, _burnAmount);
    }

    emit LogDistribute(_token, _revenueAmount, _devAmount, _burnAmount);
  }

  function _allocate(uint256 _amount)
    internal
    view
    returns (
      uint256 _revenueAmount,
      uint256 _devAmount,
      uint256 _burnAmount
    )
  {
    if (_amount != 0) {
      uint256 _totalAllocPoint = revenueAllocPoint + devAllocPoint + burnAllocPoint;
      _devAmount = (_amount * devAllocPoint) / _totalAllocPoint;
      _burnAmount = (_amount * burnAllocPoint) / _totalAllocPoint;
      unchecked {
        _revenueAmount = _amount - _devAmount - _burnAmount;
      }
    }
  }

  function withdraw(address[] calldata _tokens, address _to) external onlyOwner {
    uint256 _length = _tokens.length;
    for (uint256 _i; _i < _length; ) {
      _withdraw(_tokens[_i], _to);
      unchecked {
        ++_i;
      }
    }
  }

  function _withdraw(address _token, address _to) internal {
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(_to, _amount);
    emit LogWithdraw(_to, _token, _amount);
  }
}
