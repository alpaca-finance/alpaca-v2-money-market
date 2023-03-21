// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { InterestBearingToken } from "solidity/contracts/money-market/InterestBearingToken.sol";

contract InterestBearingTokenBaseTest is MoneyMarket_BaseTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function deployInterestBearingToken(address _underlyingToken) internal returns (InterestBearingToken) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/InterestBearingToken.sol/InterestBearingToken.json")
    );
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _underlyingToken,
      moneyMarketDiamond
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return InterestBearingToken(_proxy);
  }

  function deployUninitializedInterestBearingToken() internal returns (InterestBearingToken) {
    bytes memory _logicBytecode = abi.encodePacked(
      vm.getCode("./out/InterestBearingToken.sol/InterestBearingToken.json")
    );
    // call view function to avoid calling initializer
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("moneyMarket()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return InterestBearingToken(_proxy);
  }
}
