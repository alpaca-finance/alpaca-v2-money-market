// SPDX-License-Identifier: BUSL
pragma solidity 0.8.17;

import "../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";
import { MockAlpacaV2Oracle } from "solidity/tests/mocks/MockAlpacaV2Oracle.sol";
import { TripleSlopeModel6 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel6.sol";
import { TripleSlopeModel7 } from "solidity/contracts/money-market/interest-models/TripleSlopeModel7.sol";

contract SetUpMMForTestScript is BaseScript {
  using stdJson for string;

  function run() public {
    _loadAddresses();

    _startDeployerBroadcast();

    //---- setup mm configs ----//
    moneyMarket.setMinDebtSize(0.1 ether);
    moneyMarket.setMaxNumOfToken(10, 10, 10);

    moneyMarket.setIbTokenImplementation(address(new InterestBearingToken()));
    moneyMarket.setDebtTokenImplementation(address(new DebtToken()));

    address irm1 = address(new TripleSlopeModel6());
    address irm2 = address(new TripleSlopeModel7());

    moneyMarket.setInterestModel(busd, irm1);
    moneyMarket.setInterestModel(wbnb, irm2);
    moneyMarket.setInterestModel(doge, irm1);
    moneyMarket.setInterestModel(dodo, irm2);

    //---- open markets ----//
    // avoid stack too deep
    {
      IAdminFacet.TokenConfigInput memory tokenConfigInput = IAdminFacet.TokenConfigInput({
        tier: LibConstant.AssetTier.COLLATERAL,
        collateralFactor: 0,
        borrowingFactor: 9000,
        maxBorrow: 1_000_000 ether,
        maxCollateral: 0
      });
      IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
        tier: LibConstant.AssetTier.COLLATERAL,
        collateralFactor: 9000,
        borrowingFactor: 9000,
        maxBorrow: 0,
        maxCollateral: 1_000_000 ether
      });
      address ibBusd = moneyMarket.openMarket(busd, tokenConfigInput, ibTokenConfigInput);

      // DODO
      tokenConfigInput.tier = LibConstant.AssetTier.CROSS;
      tokenConfigInput.borrowingFactor = 8500;
      tokenConfigInput.maxBorrow = 1_000_000 ether;

      ibTokenConfigInput.tier = LibConstant.AssetTier.CROSS;
      ibTokenConfigInput.collateralFactor = 0;
      ibTokenConfigInput.maxCollateral = 0;
      address ibDodo = moneyMarket.openMarket(dodo, tokenConfigInput, ibTokenConfigInput);

      // DOGE
      tokenConfigInput.tier = LibConstant.AssetTier.ISOLATE;
      tokenConfigInput.borrowingFactor = 8000;
      tokenConfigInput.maxBorrow = 1_000_000 ether;

      ibTokenConfigInput.tier = LibConstant.AssetTier.ISOLATE;
      ibTokenConfigInput.collateralFactor = 0;
      ibTokenConfigInput.maxCollateral = 0;
      address ibDoge = moneyMarket.openMarket(doge, tokenConfigInput, ibTokenConfigInput);

      _writeJson(vm.toString(ibBusd), ".ibTokens.ibBusd");
      _writeJson(vm.toString(ibDodo), ".ibTokens.ibDodo");
      _writeJson(vm.toString(ibDoge), ".ibTokens.ibDoge");
    }

    _stopBroadcast();

    //---- setup user positions ----//

    _startUserBroadcast();

    MockERC20(wbnb).approve(address(accountManager), type(uint256).max);
    MockERC20(busd).approve(address(accountManager), type(uint256).max);
    MockERC20(dodo).approve(address(accountManager), type(uint256).max);
    MockERC20(doge).approve(address(accountManager), type(uint256).max);

    // seed money market
    accountManager.deposit(dodo, 10 ether);
    accountManager.deposit(doge, 10e8);

    // subAccount 0
    accountManager.depositAndAddCollateral(0, wbnb, 78.09 ether);
    accountManager.depositAndAddCollateral(0, busd, 12.2831207 ether);

    accountManager.borrow(0, dodo, 3.14159 ether);

    // subAccount 1
    accountManager.depositAndAddCollateral(1, busd, 10 ether);

    accountManager.borrow(1, doge, 2.34e8);

    _stopBroadcast();
  }
}
