// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../../BaseScript.sol";

import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { LibConstant } from "solidity/contracts/money-market/libraries/LibConstant.sol";

contract OpenMarketScript is BaseScript {
  using stdJson for string;

  struct OpenMarketInput {
    address token;
    address interestModel;
    LibConstant.AssetTier tier;
    uint16 collateralFactor;
    uint16 borrowingFactor;
    uint256 maxCollateral;
    uint256 maxBorrow;
  }

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
    _startDeployerBroadcast();

    // DOGE
    executeOpenMarket(
      OpenMarketInput({
        token: doge,
        interestModel: doubleSlope1,
        tier: LibConstant.AssetTier.COLLATERAL,
        collateralFactor: 3000,
        borrowingFactor: 5000,
        maxCollateral: formatAmount(doge, 15_000_000),
        maxBorrow: formatAmount(doge, 10_000_000)
      })
    );

    // LTC
    executeOpenMarket(
      OpenMarketInput({
        token: ltc,
        interestModel: doubleSlope1,
        tier: LibConstant.AssetTier.COLLATERAL,
        collateralFactor: 5000,
        borrowingFactor: 7500,
        maxCollateral: formatAmount(ltc, 120_000),
        maxBorrow: formatAmount(ltc, 100_000)
      })
    );

    _stopBroadcast();
  }

  function executeOpenMarket(OpenMarketInput memory _input) internal {
    // prepare input
    IAdminFacet.TokenConfigInput memory underlyingTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: _input.tier,
      collateralFactor: 0,
      borrowingFactor: _input.borrowingFactor,
      maxBorrow: _input.maxBorrow,
      maxCollateral: 0 ether
    });

    IAdminFacet.TokenConfigInput memory ibTokenConfigInput = IAdminFacet.TokenConfigInput({
      tier: _input.tier,
      collateralFactor: _input.collateralFactor,
      borrowingFactor: 1, // 1 for preventing divided by zero
      maxBorrow: 0,
      maxCollateral: _input.maxCollateral
    });

    // open market
    moneyMarket.openMarket(_input.token, underlyingTokenConfigInput, ibTokenConfigInput);
    // set interest model to market
    moneyMarket.setInterestModel(_input.token, _input.interestModel);

    // write result to json
    writeNewMarketToJson(_input.token);
    writeNewMiniFLPoolToJson(moneyMarket.getIbTokenFromToken(_input.token));
    writeNewMiniFLPoolToJson(moneyMarket.getDebtTokenFromToken(_input.token));
  }

  function formatAmount(address _token, uint256 _amount) internal returns (uint256 _formatAmount) {
    _formatAmount = _amount * 10**(IERC20(_token).decimals());
  }

  function writeNewMarketToJson(address _underlyingToken) internal {
    string[] memory cmds = new string[](15);
    cmds[0] = "npx";
    cmds[1] = "ts-node";
    cmds[2] = "./type-script/scripts/write-new-market.ts";
    cmds[3] = "--name";
    cmds[4] = IERC20(_underlyingToken).symbol();
    cmds[5] = "--tier";
    cmds[6] = vm.toString(uint8(moneyMarket.getTokenConfig(_underlyingToken).tier));
    cmds[7] = "--token";
    cmds[8] = vm.toString(_underlyingToken);
    cmds[9] = "--ibToken";
    cmds[10] = vm.toString(moneyMarket.getIbTokenFromToken(_underlyingToken));
    cmds[11] = "--debtToken";
    cmds[12] = vm.toString(moneyMarket.getDebtTokenFromToken(_underlyingToken));
    cmds[13] = "--interestModel";
    cmds[14] = vm.toString(moneyMarket.getOverCollatInterestModel(_underlyingToken));

    vm.ffi(cmds);
  }

  function writeNewMiniFLPoolToJson(address _stakingToken) internal {
    string[] memory cmds = new string[](9);
    cmds[0] = "npx";
    cmds[1] = "ts-node";
    cmds[2] = "./type-script/scripts/write-mini-fl-pool.ts";
    cmds[3] = "--id";
    cmds[4] = vm.toString(moneyMarket.getMiniFLPoolIdOfToken(_stakingToken));
    cmds[5] = "--name";
    cmds[6] = IERC20(_stakingToken).symbol();
    cmds[7] = "--stakingToken";
    cmds[8] = vm.toString(_stakingToken);

    vm.ffi(cmds);
  }
}
