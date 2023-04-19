// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "solidity/tests/utils/Components.sol";

import { PancakeswapV3IbTokenLiquidationStrategy } from "solidity/contracts/money-market/PancakeswapV3IbTokenLiquidationStrategy.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IPancakeV3Factory } from "solidity/contracts/money-market/interfaces/IPancakeV3Factory.sol";
import { IV3SwapRouter } from "solidity/contracts/money-market/interfaces/IV3SwapRouter.sol";
import { IAdminFacet } from "solidity/contracts/money-market/interfaces/IAdminFacet.sol";

// Mock
import { MockERC20 } from "solidity/tests/mocks/MockERC20.sol";
import { MockMoneyMarket } from "../../mocks/MockMoneyMarket.sol";

// Library
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract BaseLiqudationV3ForkTest is DSTest, StdUtils, StdAssertions, StdCheats {
  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  string internal BSC_URL_RPC = "https://bsc-dataseed2.ninicoin.io";

  // Users
  address internal constant ALICE = address(0x88);
  address internal constant BOB = address(0x168);

  IPancakeV3Factory internal PANCAKE_V3_FACTORY = IPancakeV3Factory(0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865);
  IV3SwapRouter internal router = IV3SwapRouter(0x13f4EA83D0bd40E75C8222255bc855a974568Dd4);

  MockERC20 internal wbnb = MockERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  MockERC20 internal cake = MockERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  MockERC20 internal usdt = MockERC20(0x55d398326f99059fF775485246999027B3197955);

  uint256 internal wbnbDecimal;
  uint256 internal cakeDecimal;
  uint256 internal usdtDecimal;

  InterestBearingToken internal ibWbnb;
  InterestBearingToken internal ibCake;
  InterestBearingToken internal ibUsdt;

  uint256 internal ibWbnbDecimal;
  uint256 internal ibCakeDecimal;
  uint256 internal ibUsdtDecimal;

  uint24 internal poolFee = 2500;

  MockMoneyMarket internal moneyMarket;
  PancakeswapV3IbTokenLiquidationStrategy internal liquidationStrat;

  function setUp() public virtual {
    vm.selectFork(vm.createFork(BSC_URL_RPC));
    vm.rollFork(27_280_390); // block 27280390

    // Underlying Token
    wbnbDecimal = wbnb.decimals();
    cakeDecimal = cake.decimals();
    usdtDecimal = usdt.decimals();

    moneyMarket = new MockMoneyMarket();

    liquidationStrat = new PancakeswapV3IbTokenLiquidationStrategy(
      address(router),
      address(moneyMarket),
      address(PANCAKE_V3_FACTORY)
    );

    address[] memory _callers = new address[](1);
    _callers[0] = ALICE;

    liquidationStrat.setCallersOk(_callers, true);

    vm.label(ALICE, "ALICE");
    vm.label(BOB, "BOB");
  }

  function normalizeEther(uint256 _ether, uint256 _decimal) internal pure returns (uint256 _normalizedEther) {
    _normalizedEther = _ether / 10**(18 - _decimal);
  }
}
