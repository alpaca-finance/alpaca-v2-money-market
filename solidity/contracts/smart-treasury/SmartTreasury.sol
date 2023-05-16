// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

// ---- External Libraries ---- //
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// ---- Libraries ---- //
import { LibSafeToken } from "../money-market/libraries/LibSafeToken.sol";
import { LibConstant } from "../money-market/libraries/LibConstant.sol";

// ---- Interfaces ---- //
import { IPancakeRouter02 } from "../money-market/interfaces/IPancakeRouter02.sol";
import { IUniSwapV2PathReader } from "../reader/interfaces/IUniSwapV2PathReader.sol";
import { IUniSwapV3PathReader } from "../reader/interfaces/IUniSwapV3PathReader.sol";
import { IPancakeSwapRouterV3 } from "../money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IERC20 } from "../money-market/interfaces/IERC20.sol";
import { ISmartTreasury } from "../interfaces/ISmartTreasury.sol";
import { IOracleMedianizer } from "../oracle/interfaces/IOracleMedianizer.sol";

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

  address public revenueTreasury;
  uint16 public revenueAllocPoint;

  address public devTreasury;
  uint16 public devAllocPoint;

  address public burnTreasury;
  uint16 public burnAllocPoint;

  address public revenueToken;

  IUniSwapV2PathReader public pathReaderV2;
  IPancakeRouter02 public routerV2;
  IUniSwapV3PathReader public pathReaderV3;
  IPancakeSwapRouterV3 public routerV3;
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
    address _pathReaderV2,
    address _routerV3,
    address _pathReaderV3,
    address _oracleMedianizer
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    routerV3 = IPancakeSwapRouterV3(_routerV3);
    pathReaderV2 = IUniSwapV2PathReader(_pathReaderV2);
    pathReaderV3 = IUniSwapV3PathReader(_pathReaderV3);
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
    // Sanity check
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

  function _distribute(address _token) internal {
    address _revenueToken = revenueToken;
    address _revenueTreasuryAddress = revenueTreasury;
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    (uint256 _revenueAmount, uint256 _devAmount, uint256 _burnAmount) = _allocate(_amount);

    if (_revenueAmount != 0) {
      if (_token == _revenueToken) {
        IERC20(_token).safeTransfer(revenueTreasury, _revenueAmount);
      } else {
        // Check path on pool v3 first
        bytes memory _v3Path = (pathReaderV3.paths(_token, _revenueToken));
        if (_v3Path.length != 0) {
          bool _success = _swapTokenV3(_token, _revenueToken, _revenueAmount, _revenueTreasuryAddress, _v3Path);
          if (!_success) {
            return;
          }
        } else {
          IUniSwapV2PathReader.PathParams memory _pathParam = pathReaderV2.getPath(_token, _revenueToken);
          if (_pathParam.path.length != 0) {
            bool _success = _swapTokenV2(_token, _revenueToken, _revenueAmount, _revenueTreasuryAddress, _pathParam);
            if (!_success) {
              return;
            }
          } else {
            revert SmartTreasury_PathConfigNotFound();
          }
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

  function _swapTokenV2(
    address _tokenIn,
    address _tokenOut,
    uint256 _amount,
    address _to,
    IUniSwapV2PathReader.PathParams memory _param
  ) internal returns (bool _success) {
    // Swap and send to revenue treasury
    IERC20(_tokenIn).safeApprove(address(_param.router), _amount);
    try
      IPancakeRouter02(_param.router).swapExactTokensForTokens(
        _amount,
        _getMinAmountOut(_tokenIn, _tokenOut, _amount),
        _param.path,
        _to,
        block.timestamp
      )
    {
      _success = true;
    } catch (bytes memory _reason) {
      emit LogFailedDistribution(_tokenIn, _reason);
      _success = false;
    }
  }

  function _swapTokenV3(
    address _tokenIn,
    address _tokenOut,
    uint256 _amount,
    address _to,
    bytes memory _path
  ) internal returns (bool _success) {
    IPancakeSwapRouterV3.ExactInputParams memory params = IPancakeSwapRouterV3.ExactInputParams({
      path: _path,
      recipient: _to,
      deadline: block.timestamp,
      amountIn: _amount,
      amountOutMinimum: _getMinAmountOut(_tokenIn, _tokenOut, _amount)
    });

    // Swap and send to revenue treasury
    IERC20(_tokenIn).safeApprove(address(routerV3), _amount);
    try routerV3.exactInput(params) {
      _success = true;
    } catch (bytes memory _reason) {
      emit LogFailedDistribution(_tokenIn, _reason);
      _success = false;
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

  /// @notice Withdraw the tokens from contracts
  /// @dev Emergency function, will use when token is stuck in this contract
  /// @param _tokens An array of address withdraw tokens
  /// @param _to Destination address
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
