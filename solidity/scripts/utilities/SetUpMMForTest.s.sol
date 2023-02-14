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

    //---- setup tokens ----//
    address bnb = _setUpMockToken("MOCKBNB", 18);
    address busd = _setUpMockToken("MOCKBUSD", 18);
    address dodo = _setUpMockToken("MOCKDODO", 18);
    address pstake = _setUpMockToken("MOCKPSTAKE", 18);
    address mock6DecimalsToken = _setUpMockToken("MOCK6", 6);

    //---- setup mock oracle ----//
    MockAlpacaV2Oracle mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(bnb, 1 ether);
    mockOracle.setTokenPrice(busd, 1 ether);
    mockOracle.setTokenPrice(dodo, 1 ether);
    mockOracle.setTokenPrice(pstake, 1 ether);
    mockOracle.setTokenPrice(mock6DecimalsToken, 1 ether);

    moneyMarket.setOracle(address(mockOracle));

    //---- setup mm configs ----//
    moneyMarket.setMinDebtSize(0.1 ether);
    moneyMarket.setMaxNumOfToken(3, 3, 3);

    moneyMarket.setIbTokenImplementation(address(new InterestBearingToken()));
    moneyMarket.setDebtTokenImplementation(address(new DebtToken()));

    //---- open markets ----//
    IAdminFacet.TokenConfigInput memory tokenConfigInput = IAdminFacet.TokenConfigInput({
      token: bnb,
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30 ether,
      maxCollateral: 100 ether
    });
    address ibBnb = moneyMarket.openMarket(bnb, tokenConfigInput, tokenConfigInput);
    tokenConfigInput.token = busd;
    address ibBusd = moneyMarket.openMarket(busd, tokenConfigInput, tokenConfigInput);
    tokenConfigInput.token = mock6DecimalsToken;
    address ibMock6 = moneyMarket.openMarket(mock6DecimalsToken, tokenConfigInput, tokenConfigInput);
    tokenConfigInput.token = dodo;
    tokenConfigInput.tier = LibMoneyMarket01.AssetTier.CROSS;
    tokenConfigInput.collateralFactor = 0;
    tokenConfigInput.maxCollateral = 0;
    address ibDodo = moneyMarket.openMarket(dodo, tokenConfigInput, tokenConfigInput);
    tokenConfigInput.token = pstake;
    tokenConfigInput.tier = LibMoneyMarket01.AssetTier.ISOLATE;
    address ibPstake = moneyMarket.openMarket(pstake, tokenConfigInput, tokenConfigInput);

    // TEMP: set user as account manager. to be migrated to router
    {
      address[] memory _accountManagers = new address[](1);
      _accountManagers[0] = userAddress;
      moneyMarket.setAccountManagersOk(_accountManagers, true);
    }

    _stopBroadcast();

    //---- setup user positions ----//

    _startUserBroadcast();
    // prepare user's tokens
    MockERC20(bnb).mint(userAddress, 100 ether);
    MockERC20(busd).mint(userAddress, 100 ether);
    MockERC20(mock6DecimalsToken).mint(userAddress, 100e6);
    MockERC20(dodo).mint(userAddress, 100 ether);
    MockERC20(pstake).mint(userAddress, 100 ether);

    MockERC20(bnb).approve(address(moneyMarket), type(uint256).max);
    MockERC20(busd).approve(address(moneyMarket), type(uint256).max);
    MockERC20(mock6DecimalsToken).approve(address(moneyMarket), type(uint256).max);
    MockERC20(dodo).approve(address(moneyMarket), type(uint256).max);
    MockERC20(pstake).approve(address(moneyMarket), type(uint256).max);

    // seed money market
    moneyMarket.deposit(userAddress, dodo, 10 ether);
    moneyMarket.deposit(userAddress, pstake, 10 ether);
    moneyMarket.deposit(userAddress, mock6DecimalsToken, 10e6);

    // subAccount 0
    moneyMarket.addCollateral(userAddress, 0, bnb, 1 ether);
    moneyMarket.addCollateral(userAddress, 0, busd, 10 ether);

    moneyMarket.borrow(0, dodo, 1 ether);
    moneyMarket.borrow(0, mock6DecimalsToken, 1e6);

    // subAccount 1
    moneyMarket.addCollateral(userAddress, 1, mock6DecimalsToken, 10e6);

    moneyMarket.borrow(1, pstake, 1 ether);

    _stopBroadcast();

    //---- write deployed addresses ----//

    console.log("write output to", configFilePath);
    string memory configJson;
    configJson.serialize("ibBnb", ibBnb);
    configJson.serialize("ibBusd", ibBusd);
    configJson.serialize("ibDodo", ibDodo);
    configJson.serialize("ibPstake", ibPstake);
    configJson = configJson.serialize("ibMock6", ibMock6);
    _writeJson(configJson, ".ibTokens");

    configJson.serialize("bnb", bnb);
    configJson.serialize("busd", busd);
    configJson.serialize("dodo", dodo);
    configJson.serialize("pstake", pstake);
    configJson = configJson.serialize("mock6DecimalsToken", mock6DecimalsToken);
    _writeJson(configJson, ".tokens");
  }
}
