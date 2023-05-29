// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../../base/BaseTest.sol";

import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { AlpacaV2Oracle02, IAlpacaV2Oracle02 } from "../../../contracts/oracle/AlpacaV2Oracle02.sol";

contract AlpacaV2Oracle02_WithPCSv3 is BaseTest {
  address constant mockRouter = address(6666);
  uint64 constant PRICE_DIFF = 10500; // 5%
  string constant BSC_URL_RPC = "https://bsc-dataseed3.defibit.io";
  address constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
  address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
  address constant BTC = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
  address constant BTC_BUSD_POOL = 0x369482C78baD380a036cAB827fE677C1903d1523;
  address constant BTC_USDT_POOL = 0x46Cf1cF8c69595804ba91dFdd8d6b960c9B0a7C4;
  address constant BUSD_USDT_POOL = 0x4f3126d5DE26413AbDCF6948943FB9D0847d9818;

  function setUp() public virtual {
    vm.selectFork(vm.createFork(BSC_URL_RPC));
    vm.rollFork(27_280_390); // block 27280390 (edited)
    oracleMedianizer = deployOracleMedianizer();

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, BUSD, usd),
      abi.encode(1e18, block.timestamp)
    );
    alpacaV2Oracle02 = new AlpacaV2Oracle02(address(oracleMedianizer), BUSD, usd);
  }

  function testCorrectness_GetPriceFromSingleHop_ShouldWork() external {
    address[] memory _pools = new address[](1);
    _pools[0] = BTC_BUSD_POOL;
    alpacaV2Oracle02.setPools(_pools);

    uint256 _btcPrice = alpacaV2Oracle02.getPriceFromV3Pool(BTC, BUSD);

    assertEq(_btcPrice, 30005142201163931868931);
  }

  function testCorrectness_GetPriceFromMultiHop_ShouldWork() external {
    address[] memory _pools = new address[](2);
    _pools[0] = BTC_USDT_POOL;
    _pools[1] = BUSD_USDT_POOL;
    alpacaV2Oracle02.setPools(_pools);

    address[] memory _paths = new address[](3);
    _paths[0] = BTC;
    _paths[1] = USDT;
    _paths[2] = BUSD;

    uint256 _btcPrice = 1e18;
    uint256 _len = _paths.length - 1;
    for (uint256 _i = 0; _i < _len; ) {
      _btcPrice = (_btcPrice * alpacaV2Oracle02.getPriceFromV3Pool(_paths[_i], _paths[_i + 1])) / 1e18;
      unchecked {
        ++_i;
      }
    }

    assertEq(_btcPrice, 30007955032950052629317);
  }

  function testCorrectness_WhenV3PriceWithSingleHopAndOraclePriceNotDiff_ShouldReturnTrue() external {
    address[] memory _pools = new address[](1);
    _pools[0] = BTC_BUSD_POOL;
    alpacaV2Oracle02.setPools(_pools);

    address[] memory _tokens = new address[](1);
    _tokens[0] = BTC;

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, BTC, usd),
      abi.encode(30005142201163931868931, block.timestamp)
    );

    alpacaV2Oracle02.isStable(BTC);
  }

  function testCorrectness_WhenV3PriceWithMultihopAndOraclePriceNotDiff_ShouldReturnTrue() external {
    address[] memory _pools = new address[](2);
    _pools[0] = BTC_USDT_POOL;
    _pools[1] = BUSD_USDT_POOL;
    alpacaV2Oracle02.setPools(_pools);

    address[] memory _tokens = new address[](1);
    _tokens[0] = BTC;

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, BTC, usd),
      abi.encode(30007955032950052629317, block.timestamp)
    );

    alpacaV2Oracle02.isStable(BTC);
  }
}
