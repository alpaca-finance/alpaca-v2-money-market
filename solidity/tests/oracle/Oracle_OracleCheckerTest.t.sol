import { BaseTest, console, MockERC20 } from "../base/BaseTest.sol";

import { ChainLinkPriceOracle } from "../../contracts/oracle/ChainLinkPriceOracle.sol";
import { OracleChecker } from "../../contracts/oracle/OracleChecker.sol";
import { IPriceOracle } from "../../contracts/oracle/interfaces/IPriceOracle.sol";
import { MockChainLinkPriceOracle } from "../mocks/MockChainLinkPriceOracle.sol";

contract Oracle_OracleCheckerTest is BaseTest {
  MockChainLinkPriceOracle oracle;
  OracleChecker oracleChecker;

  uint256 INITIAL_TIMESTAMP = 100;
  uint256 PRICE_STALE_TIMESTAMP = 90;

  function setUp() public virtual {
    // move current timestamp to INITIAL
    vm.warp(INITIAL_TIMESTAMP);
    oracle = new MockChainLinkPriceOracle();
    oracle.add(address(weth), address(usd), 1 ether, PRICE_STALE_TIMESTAMP);
    oracle.add(address(usdc), address(usd), 1 ether, INITIAL_TIMESTAMP);

    vm.startPrank(DEPLOYER);
    oracleChecker = new OracleChecker();
    oracleChecker.initialize(IPriceOracle(address(oracle)), address(usd));
    oracleChecker.setExpiredToleranceSecond(address(weth), 5);
    oracleChecker.setPriceToleranceBps(address(weth), 100);

    oracleChecker.setExpiredToleranceSecond(address(usdc), 5);
    oracleChecker.setPriceToleranceBps(address(usdc), 100);

    vm.stopPrank();
  }

  function testCorrectness_WhenOwnerSetExpiredToleranceSecond_shouldPass() external {
    vm.prank(DEPLOYER);
    uint256 expectedMaxSecondsExpired = 60 * 5;
    oracleChecker.setExpiredToleranceSecond(address(weth), expectedMaxSecondsExpired);

    (uint256 maxSecondsExpired, ) = oracleChecker.oracleTokenConfig(address(weth));

    assertEq(maxSecondsExpired, expectedMaxSecondsExpired);
  }

  function testRevert_WhenNotOwnerSetExpiredToleranceSecond_shouldRevertNotOwner() external {
    uint256 expectedMaxSecondsExpired = 60 * 5;
    try oracleChecker.setExpiredToleranceSecond(address(weth), expectedMaxSecondsExpired) {
      fail();
    } catch Error(string memory reason) {
      assertEq(reason, "Ownable: caller is not the owner", "upgrade not owner");
    }
  }

  function testCorrectness_WhenOwnerSetPriceToleranceBps_shouldPass() external {
    vm.prank(DEPLOYER);
    uint16 expectedToleranceBps = 100;
    oracleChecker.setPriceToleranceBps(address(weth), expectedToleranceBps);

    (, uint16 toleranceBps) = oracleChecker.oracleTokenConfig(address(weth));
    assertEq(toleranceBps, expectedToleranceBps);
  }

  function testRevert_WhenNotOwnerSetPriceToleranceBps_shouldRevertNotOwner() external {
    uint16 expectedToleranceBps = 100;
    try oracleChecker.setPriceToleranceBps(address(weth), expectedToleranceBps) {
      fail();
    } catch Error(string memory reason) {
      assertEq(reason, "Ownable: caller is not the owner", "upgrade not owner");
    }
  }

  function testRevert_WhenOwnerSetPriceToleranceBpsTooHigh_shouldRevertToleranceTooHigh() external {
    vm.prank(DEPLOYER);
    uint16 exceedToleranceBPS = 10001;
    vm.expectRevert(OracleChecker.OracleChecker_ToleranceTooHigh.selector);
    oracleChecker.setPriceToleranceBps(address(weth), exceedToleranceBPS);
  }

  function testCorrectness_whenUsergetTokenPrice_shouldPass() external {
    (uint256 _price, uint256 _lastTimestamp) = oracleChecker.getTokenPrice(address(usdc));
    assertEq(_price, 1 ether);
    assertEq(_lastTimestamp, INITIAL_TIMESTAMP);
  }

  function testRevert_whenUserGetOldTokenPriceData_shouldRevertPriceStale() external {
    vm.expectRevert(OracleChecker.OracleChecker_PriceStale.selector);
    oracleChecker.getTokenPrice(address(weth));
  }
}
