// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../utils/Components.sol";
import { HAYWombatRouterWrapper } from "solidity/contracts/oracle/HAYWombatRouterWrapper.sol";
import { IWombatRouter } from "solidity/contracts/oracle/interfaces/IWombatRouter.sol";
import { IAlpacaV2Oracle } from "solidity/contracts/oracle/interfaces/IAlpacaV2Oracle.sol";
import { OracleMedianizer } from "solidity/contracts/oracle/OracleMedianizer.sol";

// implementation

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";

contract HAYWombatWrapper_GetAmountInTest is DSTest, StdUtils, StdAssertions, StdCheats {
  using stdStorage for StdStorage;

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  address internal constant DEPLOYER = 0xC44f82b07Ab3E691F826951a6E335E1bC1bB0B51;

  IERC20 internal constant USDT = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 internal constant USDC = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 internal constant BUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
  IERC20 internal constant HAY = IERC20(0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5);

  address internal constant USD = 0x115dffFFfffffffffFFFffffFFffFfFfFFFFfFff;

  IWombatRouter internal wombatRouter;
  IAlpacaV2Oracle internal oracle;
  OracleMedianizer internal medianizer;

  HAYWombatRouterWrapper internal wrapper;

  address internal constant HAYPOOL = 0x0520451B19AD0bb00eD35ef391086A692CFC74B2;
  address internal constant MAINPOOL = 0x312Bc7eAAF93f1C60Dc5AfC115FcCDE161055fb0;

  uint256 internal constant AMOUNTIN = 100000 * 1e18;

  function setUp() public virtual {
    vm.createSelectFork("bsc_mainnet", 28_285_417);
    wombatRouter = IWombatRouter(0x19609B03C976CCA288fbDae5c21d4290e9a4aDD7);
    oracle = IAlpacaV2Oracle(0x0Ece0910fCB2838Fbfd6bC01da17F1E96ae1D812);
    medianizer = OracleMedianizer(0x553b8adc2Ac16491Ec57239BeA7191719a2B880c);
    wrapper = new HAYWombatRouterWrapper();
  }

  function testCorrectness_WhenGetAmountIn_ShouldReturnCorrectValue() external {
    address[] memory _tokenPaths = new address[](3);
    _tokenPaths[0] = address(HAY);
    _tokenPaths[1] = address(BUSD);
    _tokenPaths[2] = address(USDT);

    address[] memory _poolPaths = new address[](2);
    _poolPaths[0] = HAYPOOL;
    _poolPaths[1] = MAINPOOL;

    (uint256 _amountOut, ) = wombatRouter.getAmountOut(_tokenPaths, _poolPaths, int256(AMOUNTIN));

    console.log(_amountOut);

    uint256[] memory _amountsFromWrapper = wrapper.getAmountsOut(AMOUNTIN, _tokenPaths);

    assertEq(_amountsFromWrapper[_amountsFromWrapper.length - 1], _amountOut);
  }

  function testRevert_WhenSourceTokenIsNotHay_ShouldRevert() external {
    address[] memory _tokenPaths = new address[](2);
    _tokenPaths[0] = address(USDC);
    _tokenPaths[1] = address(USDT);

    vm.expectRevert(abi.encodePacked("!HAY"));
    wrapper.getAmountsOut(1e18, _tokenPaths);
  }

  function testCorrectness_WhenSetOracleTokenConfigUsingWrapper_ShouldWork() external {
    address[] memory _tokenPaths = new address[](3);
    _tokenPaths[0] = address(HAY);
    _tokenPaths[1] = address(BUSD);
    _tokenPaths[2] = address(USDT);

    address[] memory _tokens = new address[](1);
    _tokens[0] = address(HAY);

    IAlpacaV2Oracle.Config[] memory _configs = new IAlpacaV2Oracle.Config[](1);
    _configs[0] = IAlpacaV2Oracle.Config({
      router: address(wrapper),
      maxPriceDiffBps: 10500,
      path: _tokenPaths,
      isUsingV3Pool: false
    });

    vm.startPrank(DEPLOYER);
    oracle.setTokenConfig(_tokens, _configs);
    vm.stopPrank();

    vm.mockCall(
      address(medianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(HAY), USD),
      abi.encode(1e18, block.timestamp)
    );
    oracle.getTokenPrice(address(HAY));

    // ensure guard mechanic
    vm.mockCall(
      address(medianizer),
      abi.encodeWithSelector(OracleMedianizer.getPrice.selector, address(HAY), USD),
      abi.encode(2e18, block.timestamp)
    );
    vm.expectRevert();
    oracle.getTokenPrice(address(HAY));
  }
}
