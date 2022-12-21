// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";
import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";

// contracts
import { AVPancakeSwapHandler } from "../../contracts/automated-vault/handlers/AVPancakeSwapHandler.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAVShareToken } from "../../contracts/automated-vault/interfaces/IAVShareToken.sol";
import { IAVPancakeSwapHandler } from "../../contracts/automated-vault/interfaces/IAVPancakeSwapHandler.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockRouter } from "../mocks/MockRouter.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;
  address internal moneyMarketDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVTradeFacet internal tradeFacet;

  address internal treasury;

  IAVPancakeSwapHandler internal handler;
  IAVShareToken internal avShareToken;

  MockLPToken internal wethUsdcLPToken;
  MockAlpacaV2Oracle internal mockOracle;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);

    adminFacet.setMoneyMarket(moneyMarketDiamond);

    // deploy lp tokens
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));

    // setup router
    MockRouter mockRouter = new MockRouter(address(wethUsdcLPToken));
    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);

    // deploy handler
    handler = IAVPancakeSwapHandler(deployAVPancakeSwapHandler(address(mockRouter), address(wethUsdcLPToken)));

    // function openVault(address _lpToken,address _stableToken,address _assetToken,uint8 _leverageLevel,uint16 _managementFeePerSec);
    avShareToken = IAVShareToken(
      adminFacet.openVault(address(wethUsdcLPToken), address(usdc), address(weth), address(handler), 3, 1)
    );

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    usdc.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup token configs
    IAVAdminFacet.TokenConfigInput[] memory tokenConfigs = new IAVAdminFacet.TokenConfigInput[](3);
    tokenConfigs[0] = IAVAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibAV01.AssetTier.TOKEN,
      maxToleranceExpiredSecond: block.timestamp
    });
    tokenConfigs[1] = IAVAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibAV01.AssetTier.TOKEN,
      maxToleranceExpiredSecond: block.timestamp
    });
    // todo: should we set this in openVault
    tokenConfigs[2] = IAVAdminFacet.TokenConfigInput({
      token: address(wethUsdcLPToken),
      tier: LibAV01.AssetTier.LP,
      maxToleranceExpiredSecond: block.timestamp
    });
    adminFacet.setTokenConfigs(tokenConfigs);

    // setup oracle
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    adminFacet.setOracle(address(mockOracle));
    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));

    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 2e18);

    // set treasury
    treasury = address(this);
    adminFacet.setTreasury(treasury);
  }

  function setUpMM() internal {
    IAdminFacet.IbPair[] memory _ibPair = new IAdminFacet.IbPair[](2);
    _ibPair[0] = IAdminFacet.IbPair({ token: address(weth), ibToken: address(ibWeth) });
    _ibPair[1] = IAdminFacet.IbPair({ token: address(usdc), ibToken: address(ibUsdc) });
    IAdminFacet(moneyMarketDiamond).setTokenToIbTokens(_ibPair);

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrower(avDiamond, true);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18,
      maxToleranceExpiredSecond: block.timestamp
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1e24,
      maxCollateral: 10e24,
      maxToleranceExpiredSecond: block.timestamp
    });

    IAdminFacet(moneyMarketDiamond).setTokenConfigs(_inputs);

    IAdminFacet.TokenBorrowLimitInput[] memory _tokenBorrowLimitInputs = new IAdminFacet.TokenBorrowLimitInput[](3);
    _tokenBorrowLimitInputs[0] = IAdminFacet.TokenBorrowLimitInput({
      token: address(weth),
      maxTokenBorrow: type(uint256).max
    });
    _tokenBorrowLimitInputs[1] = IAdminFacet.TokenBorrowLimitInput({
      token: address(usdc),
      maxTokenBorrow: type(uint256).max
    });
    _tokenBorrowLimitInputs[2] = IAdminFacet.TokenBorrowLimitInput({
      token: address(btc),
      maxTokenBorrow: type(uint256).max
    });

    IAdminFacet.ProtocolConfigInput[] memory _protocolConfigInputs = new IAdminFacet.ProtocolConfigInput[](2);
    _protocolConfigInputs[0] = IAdminFacet.ProtocolConfigInput({
      account: avDiamond,
      tokenBorrowLimit: _tokenBorrowLimitInputs,
      borrowLimitUSDValue: type(uint256).max
    });

    IAdminFacet(moneyMarketDiamond).setProtocolConfigs(_protocolConfigInputs);

    // TODO: remove
    IAdminFacet.NonCollatBorrowLimitInput[] memory _limitInputs = new IAdminFacet.NonCollatBorrowLimitInput[](1);
    _limitInputs[0] = IAdminFacet.NonCollatBorrowLimitInput({ account: avDiamond, limit: 1000 ether });

    IAdminFacet(moneyMarketDiamond).setNonCollatBorrowLimitUSDValues(_limitInputs);
    // ***

    // prepare for borrow
    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(address(weth), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 100 ether);
    vm.stopPrank();
  }

  function deployAVPancakeSwapHandler(address _router, address _lpToken) internal returns (AVPancakeSwapHandler) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/AVPancakeSwapHandler.sol/AVPancakeSwapHandler.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _router,
      _lpToken
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return AVPancakeSwapHandler(_proxy);
  }
}
