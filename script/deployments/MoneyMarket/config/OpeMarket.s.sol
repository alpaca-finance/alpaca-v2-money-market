// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "solidity/contracts/money-market/DebtToken.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract OpenMarketScript is BaseScript {
  using stdJson for string;

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

    //---- inputs ----//
    uint8 newMarketLength = 3;
    address[] memory underlyingTokens = new address[](newMarketLength);
    IAdminFacet.TokenConfigInput[] memory underlyingTokenConfigInputs = new IAdminFacet.TokenConfigInput[](
      newMarketLength
    );
    IAdminFacet.TokenConfigInput[] memory ibTokenConfigInputs = new IAdminFacet.TokenConfigInput[](newMarketLength);

    // WBNB
    underlyingTokens[0] = wbnb;
    underlyingTokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    ibTokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxBorrow: 0 ether,
      maxCollateral: 1_000_000 ether
    });

    // BUSD
    underlyingTokens[1] = busd;
    underlyingTokenConfigInputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    ibTokenConfigInputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxBorrow: 0 ether,
      maxCollateral: 1_000_000 ether
    });

    // // ALPACA
    underlyingTokens[2] = alpaca;
    underlyingTokenConfigInputs[2] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    ibTokenConfigInputs[2] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 1,
      maxBorrow: 0 ether,
      maxCollateral: 1_000_000 ether
    });

    // CAKE
    // underlyingTokens[3] = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    // underlyingTokenConfigInputs[3] = IAdminFacet.TokenConfigInput({
    //   tier: LibConstant.AssetTier.ISOLATE,
    //   collateralFactor: 0,
    //   borrowingFactor: 8500,
    //   maxBorrow: 10_000 ether,
    //   maxCollateral: 0 ether
    // });
    // ibTokenConfigInputs[3] = IAdminFacet.TokenConfigInput({
    //   tier: LibConstant.AssetTier.ISOLATE,
    //   collateralFactor: 0,
    //   borrowingFactor: 1,
    //   maxBorrow: 0 ether,
    //   maxCollateral: 1_000_000 ether
    // });

    //---- execution ----//
    _startDeployerBroadcast();

    for (uint256 i; i < newMarketLength; i++) {
      address newIbToken = moneyMarket.openMarket(
        underlyingTokens[i],
        underlyingTokenConfigInputs[i],
        ibTokenConfigInputs[i]
      );

      address newDebtToken = moneyMarket.getDebtTokenFromToken(underlyingTokens[i]);

      console.log("*** Open Market for ***");
      console.log("underlyingToken", underlyingTokens[i]);

      console.log("newIbToken:", newIbToken, "pId:", moneyMarket.getMiniFLPoolIdOfToken(newIbToken));

      console.log(
        "debtToken:",
        moneyMarket.getDebtTokenFromToken(underlyingTokens[i]),
        "pId:",
        moneyMarket.getMiniFLPoolIdOfToken(newDebtToken)
      );
      console.log("");
    }

    _stopBroadcast();

    // TODO: add new ib and debt token in miniFL pools
    // string memory configJson;
    // configJson = configJson.serialize("newIbToken", newIbToken);
    // configJson.write(configFilePath, ".IbTokens");
  }
}
