// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../base/BaseTest.sol";

import { OracleMedianizer } from "../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { IAlpacaV2Oracle } from "../../contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { IRouterLike } from "../../contracts/oracle/interfaces/IRouterLike.sol";

contract AlpacaV2Oracle_IsStableTest is BaseTest {
  address constant mockRouter = address(6666);
  uint64 constant PRICE_DIFF = 10500; // 5%

  function setUp() public virtual {
    oracleMedianizer = deployOracleMedianizer();

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(busd), usd),
      abi.encode(1e18, block.timestamp)
    );
    alpacaV2Oracle = deployAlpacaV2Oracle(address(oracleMedianizer), address(busd));

    // setup token config

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(usdc);

    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);
    _configs[0] = IAlpacaV2Oracle.Config({
      router: mockRouter,
      maxPriceDiffBps: PRICE_DIFF,
      path: _usdcPath,
      useV3: false
    });

    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }

  function testCorrectness_WhenDexAndOraclePriceNotDiff_ShouldReturnTrue() external {
    uint256 _usdcOraclePrice = normalizeEther(1 ether, usdDecimal);

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(usdc), usd),
      abi.encode(_usdcOraclePrice, block.timestamp)
    );

    // mock amountOut from router
    uint256[] memory _mockAmtOut = new uint256[](2);
    _mockAmtOut[0] = _usdcOraclePrice;
    _mockAmtOut[1] = _usdcOraclePrice;

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    vm.mockCall(
      address(mockRouter),
      abi.encodeWithSelector(IRouterLike.getAmountsOut.selector, normalizeEther(1 ether, usdcDecimal), _usdcPath),
      abi.encode(_mockAmtOut)
    );

    alpacaV2Oracle.isStable(address(usdc));
  }

  function testRevert_WhenDexPriceTooLow_ShouldRevert() external {
    uint256 _usdcOraclePrice = normalizeEther(1 ether, usdDecimal);
    uint256 _usdcDexPrice = normalizeEther(0.95 ether, usdDecimal);

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(usdc), usd),
      abi.encode(_usdcOraclePrice, block.timestamp)
    );

    // mock amountOut from router
    uint256[] memory _mockAmtOut = new uint256[](2);
    _mockAmtOut[0] = _usdcOraclePrice;
    _mockAmtOut[1] = _usdcDexPrice;

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    vm.mockCall(
      address(mockRouter),
      abi.encodeWithSelector(IRouterLike.getAmountsOut.selector, normalizeEther(1 ether, usdcDecimal), _usdcPath),
      abi.encode(_mockAmtOut)
    );

    vm.expectRevert(
      abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_PriceTooDeviate.selector, _usdcDexPrice, _usdcOraclePrice)
    );
    alpacaV2Oracle.isStable(address(usdc));
  }

  function testRevert_WhenDexPriceTooHigh_ShouldRevert() external {
    uint256 _usdcOraclePrice = normalizeEther(1 ether, usdDecimal);
    uint256 _usdcDexPrice = normalizeEther(1.05 ether + 1, usdDecimal);

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(usdc), usd),
      abi.encode(_usdcOraclePrice, block.timestamp)
    );

    // mock amountOut from router
    uint256[] memory _mockAmtOut = new uint256[](2);
    _mockAmtOut[0] = _usdcOraclePrice;
    _mockAmtOut[1] = _usdcDexPrice;

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    vm.mockCall(
      address(mockRouter),
      abi.encodeWithSelector(IRouterLike.getAmountsOut.selector, normalizeEther(1 ether, usdcDecimal), _usdcPath),
      abi.encode(_mockAmtOut)
    );

    vm.expectRevert(
      abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_PriceTooDeviate.selector, _usdcDexPrice, _usdcOraclePrice)
    );
    alpacaV2Oracle.isStable(address(usdc));
  }

  function testCorrectness_WhenTokenIsBaseStable_ShouldWork() external view {
    alpacaV2Oracle.isStable(address(busd));
  }

  function testRevert_WhenTokenConfigNotSet_ShouldRevert() external {
    uint256 _btcOraclePrice = normalizeEther(1 ether, usdDecimal);
    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(btc), usd),
      abi.encode(_btcOraclePrice, block.timestamp)
    );

    vm.expectRevert();
    alpacaV2Oracle.isStable(address(btc));
  }
}
