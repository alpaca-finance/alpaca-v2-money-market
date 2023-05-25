// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { DSTest } from "solidity/tests/base/DSTest.sol";
import "../utils/Components.sol";

// interfaces
import { IERC20 } from "solidity/contracts/money-market/interfaces/IERC20.sol";
import { IUniSwapV3PathReader } from "solidity/contracts/reader/interfaces/IUniSwapV3PathReader.sol";
import { IPancakeV3PoolState } from "solidity/contracts/money-market/interfaces/IPancakeV3Pool.sol";

// implementation
import { PCSV3PathReader } from "solidity/contracts/reader/PCSV3PathReader.sol";

contract PCSV3PathReaderTest is DSTest, StdUtils, StdAssertions, StdCheats {
  using stdStorage for StdStorage;

  address DEPLOYER = makeAddr("DEPLOYER");

  VM internal constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  IERC20 public constant btcb = IERC20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);
  IERC20 public constant eth = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
  IERC20 public constant wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
  IERC20 public constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
  IERC20 public constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
  IERC20 public constant cake = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  IERC20 public constant doge = IERC20(0xbA2aE424d960c26247Dd6c32edC70B295c744C43);

  IUniSwapV3PathReader pcsPathReaderV3;

  function setUp() public {
    vm.createSelectFork("bsc_mainnet", 28_113_725);

    vm.prank(DEPLOYER);
    pcsPathReaderV3 = new PCSV3PathReader();
  }

  function testRevert_UnauthorizedSetPath_ShouldRevert() external {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 2500;
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(_token0, _poolFee, _token1);

    vm.expectRevert("Ownable: caller is not the owner");
    pcsPathReaderV3.setPaths(_paths);
  }

  function testCorrectness_SetPathV3_ShouldWork() external {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 2500;
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(_token0, _poolFee, _token1);

    vm.prank(DEPLOYER);
    pcsPathReaderV3.setPaths(_paths);

    assertEq(pcsPathReaderV3.paths(_token0, _token1), _paths[0]);
  }

  function testRevert_SetInvalidTokenPath_ShouldRevert() external {
    address _token0 = address(usdt);
    address _token1 = address(wbnb);
    uint24 _poolFee = 5000;
    bytes[] memory _paths = new bytes[](1);
    _paths[0] = abi.encodePacked(_token0, _poolFee, _token1);

    vm.prank(DEPLOYER);
    // evm revert if pool address is not existing
    vm.expectRevert();
    pcsPathReaderV3.setPaths(_paths);

    // bypass pool address revert, to check if liquidity is 0
    address _poolAddress = _computeAddressV3(_token0, _token1, _poolFee);

    vm.mockCall(_poolAddress, abi.encodeWithSelector(IPancakeV3PoolState.liquidity.selector), abi.encode(0));

    vm.prank(DEPLOYER);
    // evm revert if pool address is not existing
    vm.expectRevert(
      abi.encodeWithSelector(PCSV3PathReader.PCSV3PathReader_NoLiquidity.selector, _token0, _token1, _poolFee)
    );
    pcsPathReaderV3.setPaths(_paths);
  }

  function testRevert_SetPathExceedMaxLength_ShouldRevert() external {
    address _token0 = address(usdt);
    uint24 _poolFee = 5000;
    bytes[] memory _paths = new bytes[](1);
    // 6 hop
    _paths[0] = abi.encodePacked(
      _token0,
      _poolFee,
      _token0,
      _poolFee,
      _token0,
      _poolFee,
      _token0,
      _poolFee,
      _token0,
      _poolFee,
      _token0,
      _poolFee,
      _token0
    );

    vm.prank(DEPLOYER);
    // evm revert if pool address is not existing
    vm.expectRevert(abi.encodeWithSignature("PCSV3PathReader_MaxPathLengthExceed()"));
    pcsPathReaderV3.setPaths(_paths);
  }

  function _computeAddressV3(
    address _tokenA,
    address _tokenB,
    uint24 _fee
  ) internal pure returns (address pool) {
    if (_tokenA > _tokenB) (_tokenA, _tokenB) = (_tokenB, _tokenA);
    pool = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              hex"ff",
              0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9,
              keccak256(abi.encode(_tokenA, _tokenB, _fee)),
              bytes32(0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2)
            )
          )
        )
      )
    );
  }
}
