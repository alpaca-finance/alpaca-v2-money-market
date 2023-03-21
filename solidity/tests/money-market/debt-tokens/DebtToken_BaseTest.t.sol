// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MoneyMarket_BaseTest, console } from "../MoneyMarket_BaseTest.t.sol";
import { DebtToken } from "../../../contracts/money-market/DebtToken.sol";

contract DebtToken_BaseTest is MoneyMarket_BaseTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function deployDebtToken(address _underlyingToken) internal returns (DebtToken) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/DebtToken.sol/DebtToken.json"));
    bytes memory _initializer = abi.encodeWithSelector(
      bytes4(keccak256("initialize(address,address)")),
      _underlyingToken,
      moneyMarketDiamond
    );
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return DebtToken(_proxy);
  }

  function deployUninitializedDebtToken() internal returns (DebtToken) {
    bytes memory _logicBytecode = abi.encodePacked(vm.getCode("./out/DebtToken.sol/DebtToken.json"));
    // call view function to avoid calling initializer
    bytes memory _initializer = abi.encodeWithSelector(bytes4(keccak256("moneyMarket()")));
    address _proxy = _setupUpgradeable(_logicBytecode, _initializer);
    return DebtToken(_proxy);
  }
}
