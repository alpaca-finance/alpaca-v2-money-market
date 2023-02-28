// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";
import { LibMoneyMarket01 } from "solidity/contracts/money-market/libraries/LibMoneyMarket01.sol";
import { MockAlpacaV2Oracle } from "solidity/tests/mocks/MockAlpacaV2Oracle.sol";

contract SetUpMMForTestScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    //---- setup mock token ----//
    address mock6DecimalsToken = _setUpMockToken("MOCK6", 6);
    _writeJson(vm.toString(mock6DecimalsToken), ".tokens.mock6DecimalsToken");

    //---- setup mock oracle ----//
    MockAlpacaV2Oracle mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(wbnb, 300 ether);
    mockOracle.setTokenPrice(busd, 1 ether);
    mockOracle.setTokenPrice(dodo, 0.13 ether);
    mockOracle.setTokenPrice(pstake, 0.12 ether);
    mockOracle.setTokenPrice(mock6DecimalsToken, 666 ether);

    moneyMarket.setOracle(address(mockOracle));

    //---- setup mm configs ----//
    moneyMarket.setMinDebtSize(0.1 ether);
    moneyMarket.setMaxNumOfToken(10, 10, 10);

    moneyMarket.setIbTokenImplementation(address(new InterestBearingToken()));
    moneyMarket.setDebtTokenImplementation(address(new DebtToken()));

    //---- open markets ----//
    // avoid stack too deep
    {
      IAdminFacet.TokenConfigInput memory tokenConfigInput = IAdminFacet.TokenConfigInput({
        tier: LibMoneyMarket01.AssetTier.CROSS,
        collateralFactor: 0,
        borrowingFactor: 9000,
        maxBorrow: 30 ether,
        maxCollateral: 0
      });
      IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
        tier: LibMoneyMarket01.AssetTier.COLLATERAL,
        collateralFactor: 9000,
        borrowingFactor: 9000,
        maxBorrow: 30 ether,
        maxCollateral: 100 ether
      });
      address ibBusd = moneyMarket.openMarket(busd, tokenConfigInput, ibTokenConfigInput);
      address ibMock6 = moneyMarket.openMarket(mock6DecimalsToken, tokenConfigInput, ibTokenConfigInput);
      ibTokenConfigInput.tier = LibMoneyMarket01.AssetTier.UNLISTED;
      ibTokenConfigInput.collateralFactor = 0;
      ibTokenConfigInput.maxCollateral = 0;
      address ibDodo = moneyMarket.openMarket(dodo, tokenConfigInput, ibTokenConfigInput);
      tokenConfigInput.tier = LibMoneyMarket01.AssetTier.ISOLATE;
      address ibPstake = moneyMarket.openMarket(pstake, tokenConfigInput, ibTokenConfigInput);

      _writeJson(vm.toString(ibBusd), ".ibTokens.ibBusd");
      _writeJson(vm.toString(ibDodo), ".ibTokens.ibDodo");
      _writeJson(vm.toString(ibPstake), ".ibTokens.ibPstake");
      _writeJson(vm.toString(ibMock6), ".ibTokens.ibMock6");
    }

    _stopBroadcast();

    //---- setup user positions ----//

    _startUserBroadcast();

    MockERC20(mock6DecimalsToken).mint(userAddress, 100e6);

    MockERC20(wbnb).approve(address(accountManager), type(uint256).max);
    MockERC20(busd).approve(address(accountManager), type(uint256).max);
    MockERC20(dodo).approve(address(accountManager), type(uint256).max);
    MockERC20(pstake).approve(address(accountManager), type(uint256).max);
    MockERC20(mock6DecimalsToken).approve(address(accountManager), type(uint256).max);

    // seed money market
    accountManager.deposit(dodo, 10 ether);
    accountManager.deposit(pstake, 10 ether);
    accountManager.deposit(mock6DecimalsToken, 10e6);

    // subAccount 0
    accountManager.depositAndAddCollateral(0, wbnb, 78.09 ether);
    accountManager.depositAndAddCollateral(0, busd, 12.2831207 ether);

    accountManager.borrow(0, dodo, 3.14159 ether);
    // accountManager.borrow(0, mock6DecimalsToken, 1.2e6);

    // subAccount 1
    accountManager.depositAndAddCollateral(1, mock6DecimalsToken, 10e6);

    accountManager.borrow(1, pstake, 2.34 ether);

    _stopBroadcast();
  }
}
