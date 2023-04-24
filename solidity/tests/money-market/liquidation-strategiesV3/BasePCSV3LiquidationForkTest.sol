// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../../utils/Components.sol";

import { PancakeswapV3IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";

// interfaces
import { IPancakeSwapRouterV3 } from "solidity/contracts/money-market/interfaces/IPancakeSwapRouterV3.sol";
import { IQuoterV2 } from "solidity/tests/interfaces/IQuoterV2.sol";
import { IBEP20 } from "solidity/tests/interfaces/IBEP20.sol";

// Mock
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";

// Library
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract BasePCSV3LiquidationForkTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  string internal BSC_URL_RPC = "https://bsc-dataseed2.ninicoin.io";

  // Users
  address internal constant ALICE = address(0x88);
  address internal constant BOB = address(0x168);
  address internal constant BSC_TOKEN_OWNER = address(0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d);
  address internal constant PANCAKE_V3_POOL_DEPLOYER = 0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9;

  IBEP20 constant ETH = IBEP20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IBEP20 constant btcb = IBEP20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IBEP20 internal wbnb = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IBEP20 internal cake = IBEP20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IBEP20 constant usdt = IBEP20(0x55d398326f99059fF775485246999027B3197955);
  MockERC20 internal ibETH;

  uint256 internal ETHDecimal;
  uint256 internal btcbDecimal;
  uint256 internal wbnbDecimal;
  uint256 internal cakeDecimal;
  uint256 internal usdtDecimal;
  uint256 internal ibETHDecimal;

  uint24 internal poolFee = 2500;

  IPancakeSwapRouterV3 internal router = IPancakeSwapRouterV3(0x1b81D678ffb9C0263b24A97847620C99d213eB14);
  IQuoterV2 internal quoterV2 = IQuoterV2(0xB048Bbc1Ee6b733FFfCFb9e9CeF7375518e25997);
  MockMoneyMarket internal moneyMarket;
  PancakeswapV3IbTokenLiquidationStrategy internal liquidationStrat;

  function setUp() public virtual {
    vm.selectFork(vm.createFork(BSC_URL_RPC));
    vm.rollFork(27_280_390); // block 27280390

    ibETH = deployMockErc20("ibETH", "ibETH", 18);
    ETHDecimal = ETH.decimals();
    btcbDecimal = btcb.decimals();
    wbnbDecimal = wbnb.decimals();
    cakeDecimal = cake.decimals();
    usdtDecimal = usdt.decimals();
    ibETHDecimal = ibETH.decimals();

    moneyMarket = new MockMoneyMarket();
    liquidationStrat = new PancakeswapV3IbTokenLiquidationStrategy(address(router), address(moneyMarket));

    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
  }

  function deployMockErc20(
    string memory name,
    string memory symbol,
    uint8 decimals
  ) internal returns (MockERC20 mockERC20) {
    mockERC20 = new MockERC20(name, symbol, decimals);
    vm.label(address(mockERC20), symbol);
  }

  function normalizeEther(uint256 _ether, uint256 _decimal) internal pure returns (uint256 _normalizedEther) {
    _normalizedEther = _ether / 10**(18 - _decimal);
  }
}
