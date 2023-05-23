// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { PancakeswapV3IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

contract SetPathsScript is BaseScript {
  using stdJson for string;

  bytes[] paths;

  function run() public {
    /*
  ░██╗░░░░░░░██╗░█████╗░██████╗░███╗░░██╗██╗███╗░░██╗░██████╗░
  ░██║░░██╗░░██║██╔══██╗██╔══██╗████╗░██║██║████╗░██║██╔════╝░
  ░╚██╗████╗██╔╝███████║██████╔╝██╔██╗██║██║██╔██╗██║██║░░██╗░
  ░░████╔═████║░██╔══██║██╔══██╗██║╚████║██║██║╚████║██║░░╚██╗
  ░░╚██╔╝░╚██╔╝░██║░░██║██║░░██║██║░╚███║██║██║░╚███║╚██████╔╝
  ░░░╚═╝░░░╚═╝░░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚══╝╚═╝╚═╝░░╚══╝░╚═════╝░
  Check all variables below before execute the deployment script
    */

    address[] memory _strats = new address[](1);
    _strats[0] = address(pancakeswapV3IbLiquidateStrat);
    bytes memory liquidationPath;

    // ********* WBNB ********* //
    // WBNB -> USDC:
    liquidationPath = encodePath(wbnb, 500, usdt, 100, usdc);
    setLiquidationPath(liquidationPath);
    // WBNB -> USDT:
    liquidationPath = encodePath(wbnb, 500, usdt);
    setLiquidationPath(liquidationPath);
    // WBNB -> BUSD:
    liquidationPath = encodePath(wbnb, 500, busd);
    setLiquidationPath(liquidationPath);
    // WBNB -> BTCB:
    liquidationPath = encodePath(wbnb, 2500, btcb);
    setLiquidationPath(liquidationPath);
    // WBNB -> ETH:
    liquidationPath = encodePath(wbnb, 2500, eth);
    setLiquidationPath(liquidationPath);

    // ********* USDC ********* //
    // USDC -> BTCB:
    liquidationPath = encodePath(usdc, 100, busd, 500, btcb);
    setLiquidationPath(liquidationPath);
    // USDC -> ETH:
    liquidationPath = encodePath(usdc, 500, eth);
    setLiquidationPath(liquidationPath);
    // USDC -> WBNB:
    liquidationPath = encodePath(usdc, 100, usdt, 500, wbnb);
    setLiquidationPath(liquidationPath);
    // USDC -> BUSD:
    liquidationPath = encodePath(usdc, 100, busd);
    setLiquidationPath(liquidationPath);
    // USDC -> USDT:
    liquidationPath = encodePath(usdc, 100, usdt);
    setLiquidationPath(liquidationPath);

    // ********* USDT ********* //
    // USDT -> BTCB:
    liquidationPath = encodePath(usdt, 500, btcb);
    setLiquidationPath(liquidationPath);
    // USDT -> ETH:
    liquidationPath = encodePath(usdt, 500, wbnb, 2500, eth);
    setLiquidationPath(liquidationPath);
    // USDT -> WBNB:
    liquidationPath = encodePath(usdt, 500, wbnb);
    setLiquidationPath(liquidationPath);
    // USDT -> BUSD:
    liquidationPath = encodePath(usdt, 100, busd);
    setLiquidationPath(liquidationPath);
    // USDT -> USDC:
    liquidationPath = encodePath(usdt, 100, usdc);
    setLiquidationPath(liquidationPath);

    // ********* BUSD ********* //
    // BUSD -> BTCB:
    liquidationPath = encodePath(busd, 500, btcb);
    setLiquidationPath(liquidationPath);
    // BUSD -> ETH:
    liquidationPath = encodePath(busd, 500, wbnb, 2500, eth);
    setLiquidationPath(liquidationPath);
    // BUSD -> WBNB:
    liquidationPath = encodePath(busd, 500, wbnb);
    setLiquidationPath(liquidationPath);
    // BUSD -> USDT:
    liquidationPath = encodePath(busd, 100, usdt);
    setLiquidationPath(liquidationPath);
    // BUSD -> USDC:
    liquidationPath = encodePath(busd, 100, usdc);
    setLiquidationPath(liquidationPath);

    // ********* BTCB ********* //
    // BTCB -> ETH
    liquidationPath = encodePath(btcb, 2500, eth);
    setLiquidationPath(liquidationPath);
    // BTCB -> WBNB
    liquidationPath = encodePath(btcb, 2500, wbnb);
    setLiquidationPath(liquidationPath);
    // BTCB -> BUSD
    liquidationPath = encodePath(btcb, 500, busd);
    setLiquidationPath(liquidationPath);
    // BTCB -> USDT
    liquidationPath = encodePath(btcb, 500, usdt);
    setLiquidationPath(liquidationPath);
    // BTCB -> USDC
    liquidationPath = encodePath(btcb, 500, busd, 100, usdc);
    setLiquidationPath(liquidationPath);

    // ********* ETH ********* //
    // ETH -> BTCB
    liquidationPath = encodePath(eth, 2500, btcb);
    setLiquidationPath(liquidationPath);
    // ETH -> WBNB
    liquidationPath = encodePath(eth, 2500, wbnb);
    setLiquidationPath(liquidationPath);
    // ETH -> BUSD
    liquidationPath = encodePath(eth, 2500, wbnb, 500, busd);
    setLiquidationPath(liquidationPath);
    // ETH -> USDT
    liquidationPath = encodePath(eth, 2500, wbnb, 500, usdt);
    setLiquidationPath(liquidationPath);
    // ETH -> USDC
    liquidationPath = encodePath(eth, 500, usdc);
    setLiquidationPath(liquidationPath);

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint8 i; i < _strats.length; i++) {
      PancakeswapV3IbTokenLiquidationStrategy(_strats[i]).setPaths(paths);
    }

    _stopBroadcast();
  }

  function encodePath(
    address _tokenA,
    uint24 _fee,
    address _tokenB
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee, _tokenB);
  }

  function encodePath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC);
  }

  function encodePath(
    address _tokenA,
    uint24 _fee0,
    address _tokenB,
    uint24 _fee1,
    address _tokenC,
    uint24 _fee2,
    address _tokenD
  ) internal pure returns (bytes memory pool) {
    pool = abi.encodePacked(_tokenA, _fee0, _tokenB, _fee1, _tokenC, _fee2, _tokenD);
  }

  function setLiquidationPath(bytes memory liquidationPath) internal {
    paths.push(liquidationPath);

    delete liquidationPath;
  }
}
