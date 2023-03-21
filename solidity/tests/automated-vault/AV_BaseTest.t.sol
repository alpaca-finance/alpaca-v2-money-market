// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { BaseTest, console } from "../base/BaseTest.sol";

// helper
import { AVDiamondDeployer } from "../helper/AVDiamondDeployer.sol";
import { TestHelper } from "../helper/TestHelper.sol";

// contracts
import { AVPancakeSwapHandler } from "../../contracts/automated-vault/handlers/AVPancakeSwapHandler.sol";
import { InterestBearingToken } from "../../contracts/money-market/InterestBearingToken.sol";
import { DebtToken } from "../../contracts/money-market/DebtToken.sol";

// interfaces
import { IAVAdminFacet } from "../../contracts/automated-vault/interfaces/IAVAdminFacet.sol";
import { IAVTradeFacet } from "../../contracts/automated-vault/interfaces/IAVTradeFacet.sol";
import { IAVRebalanceFacet } from "../../contracts/automated-vault/interfaces/IAVRebalanceFacet.sol";
import { IAVViewFacet } from "../../contracts/automated-vault/interfaces/IAVViewFacet.sol";
import { IAVVaultToken } from "../../contracts/automated-vault/interfaces/IAVVaultToken.sol";
import { IAVHandler } from "../../contracts/automated-vault/interfaces/IAVHandler.sol";
import { IAdminFacet } from "../../contracts/money-market/interfaces/IAdminFacet.sol";
import { ILendFacet } from "../../contracts/money-market/interfaces/ILendFacet.sol";

// libraries
import { LibAVConstant } from "../../contracts/automated-vault/libraries/LibAVConstant.sol";
import { LibConstant } from "../../contracts/money-market/libraries/LibConstant.sol";
import { LibMoneyMarketDeployment } from "../../scripts/deployments/libraries/LibMoneyMarketDeployment.sol";

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
  IAVVaultToken internal vaultToken;

  MockRouter internal mockRouter;
  MockLPToken internal usdcWethLPToken;
  MockAlpacaV2Oracle internal mockOracle;

  function setUp() public virtual {
    (avDiamond, ) = AVDiamondDeployer.deployAVDiamond();

    (moneyMarketDiamond, ) = LibMoneyMarketDeployment.deployMoneyMarketDiamond(address(miniFL));

    setUpMM();

    // setup oracle
    mockOracle = new MockAlpacaV2Oracle();

    // set av facets
    adminFacet = IAVAdminFacet(avDiamond);
    tradeFacet = IAVTradeFacet(avDiamond);
    rebalanceFacet = IAVRebalanceFacet(avDiamond);
    viewFacet = IAVViewFacet(avDiamond);

    adminFacet.setMoneyMarket(moneyMarketDiamond);

    // deploy lp tokens
    usdcWethLPToken = new MockLPToken("MOCK LP", "MOCK LP", 18, address(usdc), address(weth));

    // setup router
    mockRouter = new MockRouter(address(usdcWethLPToken));
    usdcWethLPToken.mint(address(mockRouter), 1000000 ether);

    // deploy handler
    handler = IAVHandler(
      deployAVPancakeSwapHandler(
        address(mockRouter),
        address(usdcWethLPToken),
        avDiamond,
        address(mockOracle),
        address(usdc),
        address(weth),
        3
      )
    );

    // setup interest rate models
    MockInterestModel mockInterestModel1 = new MockInterestModel(0);
    MockInterestModel mockInterestModel2 = new MockInterestModel(0);

    // function openVault(address _lpToken,address _stableToken,address _assetToken,uint8 _leverageLevel,uint16 _managementFeePerSec);
    vaultToken = IAVVaultToken(
      adminFacet.openVault(
        address(usdcWethLPToken),
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
    tokenConfigs[0] = IAVAdminFacet.TokenConfigInput({ token: address(weth), tier: LibAVConstant.AssetTier.TOKEN });
    tokenConfigs[1] = IAVAdminFacet.TokenConfigInput({ token: address(usdc), tier: LibAVConstant.AssetTier.TOKEN });
    // todo: should we set this in openVault
    tokenConfigs[2] = IAVAdminFacet.TokenConfigInput({
      token: address(usdcWethLPToken),
      tier: LibAVConstant.AssetTier.LP
    });
    adminFacet.setTokenConfigs(tokenConfigs);

    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);

    adminFacet.setOracle(address(mockOracle));
    // set oracle in MM
    IAdminFacet(moneyMarketDiamond).setOracle(address(mockOracle));

    mockOracle.setTokenPrice(address(weth), 1e18);
    mockOracle.setTokenPrice(address(usdc), 1e18);
    mockOracle.setLpTokenPrice(address(usdcWethLPToken), 2e18);

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

    // set ibToken and debtToken implementation
    // warning: this one should set before open market
    mmAdminFacet.setIbTokenImplementation(address(new InterestBearingToken()));
    mmAdminFacet.setDebtTokenImplementation(address(new DebtToken()));

    address[] memory _whitelistedCallers = new address[](1);
    _whitelistedCallers[0] = moneyMarketDiamond;
    miniFL.setWhitelistedCallers(_whitelistedCallers, true);

    ibWeth = TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(weth));
    ibUsdc = TestHelper.openMarketWithDefaultTokenConfig(moneyMarketDiamond, address(usdc));

    mmAdminFacet.setNonCollatBorrowerOk(avDiamond, true);

    address[] memory _tokens = new address[](2);
    _tokens[0] = address(weth);
    _tokens[1] = address(usdc);

    IAdminFacet.TokenConfigInput[] memory _inputs = new IAdminFacet.TokenConfigInput[](2);
    _inputs[0] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: 30e18,
      maxCollateral: 100e18
    });
    _inputs[1] = IAdminFacet.TokenConfigInput({
      tier: LibConstant.AssetTier.COLLATERAL,
      collateralFactor: 9000,
      borrowingFactor: 9000,
      maxBorrow: normalizeEther(1e24, usdcDecimal),
      maxCollateral: normalizeEther(10e24, usdcDecimal)
    });

    mmAdminFacet.setTokenConfigs(_tokens, _inputs);

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
      borrowingPowerLimit: type(uint256).max
    });

    mmAdminFacet.setProtocolConfigs(_protocolConfigInputs);
    // set account manager to allow interactions
    address[] memory _accountManagers = new address[](1);
    _accountManagers[0] = EVE;

    mmAdminFacet.setAccountManagersOk(_accountManagers, true);
    // prepare for borrow
    vm.startPrank(EVE);
    weth.approve(moneyMarketDiamond, type(uint256).max);
    usdc.approve(moneyMarketDiamond, type(uint256).max);

    ILendFacet(moneyMarketDiamond).deposit(EVE, address(weth), 100 ether);
    ILendFacet(moneyMarketDiamond).deposit(EVE, address(usdc), normalizeEther(100 ether, usdcDecimal));
    vm.stopPrank();

    mmAdminFacet.setMaxNumOfToken(3, 3, 3);
  }

  function deployAVPancakeSwapHandler(
    address _router,
    address _lpToken,
    address _avDiamond,
    address _oracle,
    address _stableToken,
    address _assetToken,
    uint8 _leverageLevel
  ) internal returns (AVPancakeSwapHandler) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/AVPancakeSwapHandler.sol/AVPancakeSwapHandler.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address,address,address,address,address,uint8)")),
      _router,
      _lpToken,
      _avDiamond,
      _oracle,
      _stableToken,
      _assetToken,
      _leverageLevel
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return AVPancakeSwapHandler(_proxy);
  }
}
