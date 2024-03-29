// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console, MockERC20 } from "../../base/BaseTest.sol";

import { OracleMedianizer } from "../../../contracts/oracle/OracleMedianizer.sol";

// ---- Interfaces ---- //
import { IAlpacaV2Oracle } from "../../../contracts/oracle/interfaces/IAlpacaV2Oracle.sol";

contract AlpacaV2Oracle_SetTokenConfigTest is BaseTest {
  function setUp() public virtual {
    oracleMedianizer = deployOracleMedianizer();

    // mock price return from OracleMedianizer
    vm.mockCall(
      address(oracleMedianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(busd), usd),
      abi.encode(1e18, block.timestamp)
    );

    alpacaV2Oracle = deployAlpacaV2Oracle(address(oracleMedianizer), address(busd));
  }

  function testCorrectness_WhenOwnerSetTokenConfig_ShouldWork() external {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(usdc);

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);
    _configs[0] = IAlpacaV2Oracle.Config({
      router: address(0),
      maxPriceDiffBps: 10500,
      path: _usdcPath,
      isUsingV3Pool: false
    });

    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }

  function testRevert_WhenNotOwnerSetTokenConfig_ShouldRevert() external {
    address[] memory _tokens = new address[](1);
    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);

    vm.prank(ALICE);
    vm.expectRevert("Ownable: caller is not the owner");
    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }

  function testRevert_WhenTokenAndConfigLengthNotEqual_ShouldRevert() external {
    address[] memory _tokens = new address[](2);
    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);

    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_InvalidConfigLength.selector));
    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }

  function testRevert_WhenConfigWrongPath_ShouldRevert() external {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(usdc);

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(btc);

    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);
    _configs[0] = IAlpacaV2Oracle.Config({
      router: address(0),
      maxPriceDiffBps: 10500,
      path: _usdcPath,
      isUsingV3Pool: false
    });

    // destination not base stable
    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_InvalidConfigPath.selector));
    alpacaV2Oracle.setTokenConfig(_tokens, _configs);

    // source not token
    _tokens[0] = address(btc);

    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    _configs[0] = IAlpacaV2Oracle.Config({
      router: address(0),
      maxPriceDiffBps: 10500,
      path: _usdcPath,
      isUsingV3Pool: false
    });
    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_InvalidConfigPath.selector));
    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }

  function testRever_WhenConfigInvalidMaxPriceDiff_ShouldRevert() external {
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(usdc);

    address[] memory _usdcPath = new address[](2);
    _usdcPath[0] = address(usdc);
    _usdcPath[1] = address(busd);

    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);
    _configs[0] = IAlpacaV2Oracle.Config({
      router: address(0),
      maxPriceDiffBps: 9999,
      path: _usdcPath,
      isUsingV3Pool: false
    });

    vm.expectRevert(abi.encodeWithSelector(IAlpacaV2Oracle.AlpacaV2Oracle_InvalidPriceDiffConfig.selector));
    alpacaV2Oracle.setTokenConfig(_tokens, _configs);
  }
}
