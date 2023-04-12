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
    uint8 newMarketLength = 2;
    address[] memory underlyingTokens = new address[](newMarketLength);
    IAdminFacet.TokenConfigInput[] memory underlyingTokenConfigInputs = new IAdminFacet.TokenConfigInput[](
      newMarketLength
    );
    IAdminFacet.TokenConfigInput[] memory ibTokenConfigInputs = new IAdminFacet.TokenConfigInput[](newMarketLength);

    // cake
    underlyingTokens[0] = cake;
    underlyingTokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.CROSS,
      collateralFactor: 0,
      borrowingFactor: 9000,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    ibTokenConfigInputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.CROSS,
      collateralFactor: 0,
      borrowingFactor: 1,
      maxBorrow: 0 ether,
      maxCollateral: 0 ether
    });

    // dot
    underlyingTokens[1] = dot;
    underlyingTokenConfigInputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.ISOLATE,
      collateralFactor: 0,
      borrowingFactor: 8500,
      maxBorrow: 10_000 ether,
      maxCollateral: 0 ether
    });
    ibTokenConfigInputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.ISOLATE,
      collateralFactor: 0,
      borrowingFactor: 1,
      maxBorrow: 0 ether,
      maxCollateral: 0 ether
    });

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
