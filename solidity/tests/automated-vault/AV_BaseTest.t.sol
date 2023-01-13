// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";
import { MMDiamondDeployer } from "../helper/MMDiamondDeployer.sol";

// contracts
import { AVPancakeSwapHandler } from "../../contracts/automated-vault/handlers/AVPancakeSwapHandler.sol";
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";
import { IAVViewFacet } from "../../contracts/automated-vault/interfaces/IAVViewFacet.sol";
import { IAVShareToken } from "../../contracts/automated-vault/interfaces/IAVShareToken.sol";
import { IAVHandler } from "../../contracts/automated-vault/interfaces/IAVHandler.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";

// libraries
import { LibAV01 } from "../../contracts/automated-vault/libraries/LibAV01.sol";
import { LibMoneyMarket01 } from "../../contracts/money-market/libraries/LibMoneyMarket01.sol";

// mocks
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockAlpacaV2Oracle } from "../mocks/MockAlpacaV2Oracle.sol";
import { MockLPToken } from "../mocks/MockLPToken.sol";
import { MockInterestModel } from "../mocks/MockInterestModel.sol";
import { MockRouter } from "../mocks/MockRouter.sol";

abstract contract AV_BaseTest is BaseTest {
  address internal avDiamond;
  address internal moneyMarketDiamond;

  // av facets
  IAVAdminFacet internal adminFacet;
  IAVTradeFacet internal tradeFacet;
  IAVRebalanceFacet internal rebalanceFacet;
  IAVViewFacet internal viewFacet;

  address internal treasury;

  IAVHandler internal handler;
  IAVShareToken internal avShareToken;

  MockRouter internal mockRouter;
  MockLPToken internal wethUsdcLPToken;
  MockAlpacaV2Oracle internal mockOracle;

  function setUp() public virtual {
    avDiamond = AVDiamondDeployer.deployPoolDiamond();
    moneyMarketDiamond = MMDiamondDeployer.deployPoolDiamond(address(nativeToken), address(nativeRelayer));
    setUpMM();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);
    rebalanceFacet = IAVRebalanceFacet(avDiamond);
    viewFacet = IAVViewFacet(avDiamond);

    adminFacet.setMoneyMarket(moneyMarketDiamond);

    // deploy lp tokens
    wethUsdcLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(weth), address(usdc));

    // setup router
    mockRouter = new MockRouter(address(wethUsdcLPToken));
    wethUsdcLPToken.mint(address(mockRouter), 1000000 ether);

    // deploy handler
    handler = IAVHandler(deployAVPancakeSwapHandler(address(mockRouter), address(wethUsdcLPToken)));

    // setup interest rate models
    MockInterestModel mockInterestModel1 = new MockInterestModel(0);
    MockInterestModel mockInterestModel2 = new MockInterestModel(0);

    // function openVault(address _lpToken,address _stableToken,address _assetToken,uint8 _leverageLevel,uint16 _managementFeePerSec);
    avShareToken = IAVShareToken(
      adminFacet.openVault(
        address(wethUsdcLPToken),
        address(usdc),
        address(weth),
        address(handler),
        3,
        0,
        address(mockInterestModel1),
        address(mockInterestModel2)
      )
    );

    // approve
    vm.startPrank(ALICE);
    weth.approve(avDiamond, type(uint256).max);
    usdc.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    weth.approve(avDiamond, type(uint256).max);
    usdc.approve(avDiamond, type(uint256).max);
    vm.stopPrank();

    // setup token configs
    IAVAdminFacet.TokenConfigInput[] memory tokenConfigs = new IAVAdminFacet.TokenConfigInput[](3);
    tokenConfigs[0] = IAVAdminFacet.TokenConfigInput({ token: address(weth), tier: LibAV01.AssetTier.TOKEN });
    tokenConfigs[1] = IAVAdminFacet.TokenConfigInput({ token: address(usdc), tier: LibAV01.AssetTier.TOKEN });
    // todo: should we set this in openVault
    tokenConfigs[2] = IAVAdminFacet.TokenConfigInput({ token: address(wethUsdcLPToken), tier: LibAV01.AssetTier.LP });
    adminFacet.setTokenConfigs(tokenConfigs);

    // setup oracle
    mockOracle = new MockAlpacaV2Oracle();
    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    adminFacet.setOracle(address(mockOracle));
    // set oracle in MM
    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));

    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setLpTokenPrice(address(wethUsdcLPToken), 2e18);

    // set treasury
    treasury = address(this);
    adminFacet.setTreasury(treasury);

    // set avHandler whitelist
    address[] memory _callersOk = new address[](2);
    _callersOk[0] = address(this);
    _callersOk[1] = address(avDiamond);
    handler.setWhitelistedCallers(_callersOk, true);
  }

  function setUpMM() internal {
    IAdminFacet mmAdminFacet = IAdminFacet(moneyMarketDiamond);

    // set ib token implementation
    // warning: this one should set before open market
    mmAdminFacet.setIbTokenImplementation(address(new InterestBearingToken()));

    address _ibWeth = mmAdminFacet.openMarket(address(weth));
    address _ibUsdc = mmAdminFacet.openMarket(address(usdc));

    ibWeth = InterestBearingToken(_ibWeth);
    ibUsdc = InterestBearingToken(_ibUsdc);

    mmAdminFacet.setNonCollatBorrowerOk(avDiamond, true);
    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);

    _inputs[0] = IAdminFacet.TokenConfigInput({
      token: address(weth),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18
    });

    _inputs[1] = IAdminFacet.TokenConfigInput({
      token: address(usdc),
      tier: LibMoneyMarket01.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 1e24,
      maxCollateral: 10e24
    });

    mmAdminFacet.setTokenConfigs(_inputs);

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

    mmAdminFacet.setProtocolConfigs(_protocolConfigInputs);

    // prepare for borrow
    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(address(weth), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(address(usdc), 100 ether);
    vm.stopPrank();

    mmAdminFacet.setMaxNumOfToken(3, 3, 3);
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
