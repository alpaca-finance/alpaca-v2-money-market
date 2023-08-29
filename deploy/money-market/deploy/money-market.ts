import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { getDeployer } from "../../utils/deployer-helper";
import { ConfigFileHelper } from "../../file-helper.ts/config-file.helper";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MoneyMarketFacet } from "../../interfaces";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const deployer = await getDeployer();
  const configFileHelper = new ConfigFileHelper();
  const config = configFileHelper.getConfig();

  // Deploy MoneyMarket Facet
  const facets = await deployMoneyMarketFacets(deployer);

  const MoneyMarketDiamondFactory = await ethers.getContractFactory("MoneyMarketDiamond", deployer);

  // Deploy MoneyMarket Diamond
  const moneyMarketDiamond = await MoneyMarketDiamondFactory.deploy(facets.diamondCutFacet, config.miniFL.proxy);

  console.log(`> 🟢 MoneyMarketDiamond address : ${moneyMarketDiamond.address}`);

  configFileHelper.setMoneyMarketDiamondDeploy(facets, moneyMarketDiamond.address);
};

async function deployMoneyMarketFacets(deployer: SignerWithAddress): Promise<MoneyMarketFacet> {
  console.log(`> Deploying facets ...`);
  const MMDiamondCutFacetFactory = await ethers.getContractFactory("MMDiamondCutFacet", deployer);
  const MMDiamondLoupeFacetFactory = await ethers.getContractFactory("MMDiamondLoupeFacet", deployer);
  const ViewFacetFactory = await ethers.getContractFactory("ViewFacet", deployer);
  const LendFacetFactory = await ethers.getContractFactory("LendFacet", deployer);
  const CollateralFacetFactory = await ethers.getContractFactory("CollateralFacet", deployer);
  const BorrowFacetFactory = await ethers.getContractFactory("BorrowFacet", deployer);
  const NonCollatBorrowFacetFactory = await ethers.getContractFactory("NonCollatBorrowFacet", deployer);
  const AdminFacetFactory = await ethers.getContractFactory("AdminFacet", deployer);
  const LiquidationFacetFactory = await ethers.getContractFactory("LiquidationFacet", deployer);
  const MMOwnershipFacetFactory = await ethers.getContractFactory("MMOwnershipFacet", deployer);
  const FlashloanFacetFactory = await ethers.getContractFactory("FlashloanFacet", deployer);

  // deploy
  const MMDiamondCutFacet = await MMDiamondCutFacetFactory.deploy();
  const MMDiamondLoupeFacet = await MMDiamondLoupeFacetFactory.deploy();
  const ViewFacet = await ViewFacetFactory.deploy();
  const LendFacet = await LendFacetFactory.deploy();
  const CollateralFacet = await CollateralFacetFactory.deploy();
  const BorrowFacet = await BorrowFacetFactory.deploy();
  const NonCollatBorrowFacet = await NonCollatBorrowFacetFactory.deploy();
  const AdminFacet = await AdminFacetFactory.deploy();
  const LiquidationFacet = await LiquidationFacetFactory.deploy();
  const MMOwnershipFacet = await MMOwnershipFacetFactory.deploy();
  const FlashloanFacet = await FlashloanFacetFactory.deploy();

  console.log(`> 🟢 AdminFacet address : ${AdminFacet.address}`);
  console.log(`> 🟢 BorrowFacet address : ${BorrowFacet.address}`);
  console.log(`> 🟢 CollateralFacet address : ${CollateralFacet.address}`);
  console.log(`> 🟢 MMDiamondCutFacet address : ${MMDiamondCutFacet.address}`);
  console.log(`> 🟢 MMDiamondLoupeFacet address : ${MMDiamondLoupeFacet.address}`);
  console.log(`> 🟢 FlashloanFacet address : ${FlashloanFacet.address}`);
  console.log(`> 🟢 LendFacet address : ${LendFacet.address}`);
  console.log(`> 🟢 LiquidationFacet address : ${LiquidationFacet.address}`);
  console.log(`> 🟢 NonCollatBorrowFacet address : ${NonCollatBorrowFacet.address}`);
  console.log(`> 🟢 MMOwnershipFacet address : ${MMOwnershipFacet.address}`);
  console.log(`> 🟢 ViewFacet address : ${ViewFacet.address}`);
  return {
    adminFacet: AdminFacet.address,
    borrowFacet: BorrowFacet.address,
    collateralFacet: CollateralFacet.address,
    diamondCutFacet: MMDiamondCutFacet.address,
    diamondLoupeFacet: MMDiamondLoupeFacet.address,
    flashloanFacet: FlashloanFacet.address,
    lendFacet: LendFacet.address,
    liquidationFacet: LiquidationFacet.address,
    nonCollatBorrowFacet: NonCollatBorrowFacet.address,
    ownershipFacet: MMOwnershipFacet.address,
    viewFacet: ViewFacet.address,
  };
}

export default func;
func.tags = ["MoneyMarketDeploy"];
