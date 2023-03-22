// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "../interfaces/IERC20.sol";

library LibSafeToken {
  function safeTransfer(
    IERC20 _token,
    address to,
    uint256 value
  ) internal {
    require(isContract(_token), "!contract");
    (bool success, bytes memory data) = address(_token).call(
      abi.encodeWithSelector(_token.transfer.selector, to, value)
    );
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransfer");
  }

  function safeTransferFrom(
    IERC20 _token,
    address from,
    address to,
    uint256 value
  ) internal {
    require(isContract(_token), "!not contract");
    (bool success, bytes memory data) = address(_token).call(
      abi.encodeWithSelector(_token.transferFrom.selector, from, to, value)
    );
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeTransferFrom");
  }

  function safeApprove(
    IERC20 _token,
    address to,
    uint256 value
  ) internal {
    require(isContract(_token), "!not contract");
    (bool success, bytes memory data) = address(_token).call(
      abi.encodeWithSelector(_token.approve.selector, to, value)
    );
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeApprove");
  }

  function safeIncreaseAllowance(
    IERC20 _token,
    address _spender,
    uint256 _addValue
  ) internal {
    require(isContract(_token), "!not contract");
    uint256 currentAllowance = _token.allowance(msg.sender, _spender);
    (bool success, bytes memory data) = address(_token).call(
      abi.encodeWithSelector(_token.approve.selector, _spender, currentAllowance + _addValue)
    );
    require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeIncreaseAllowance");
  }

  function safeDecreaseAllowance(
    IERC20 _token,
    address _spender,
    uint256 _substractValue
  ) internal {
    unchecked {
      require(isContract(_token), "!not contract");
      uint256 currentAllowance = _token.allowance(address(this), _spender);
      require(currentAllowance >= _substractValue, "LibSafeToken: decreased allowance below zero");
      (bool success, bytes memory data) = address(_token).call(
        abi.encodeWithSelector(_token.approve.selector, _spender, currentAllowance - _substractValue)
      );
      require(success && (data.length == 0 || abi.decode(data, (bool))), "!safeDecreaseAllowance");
    }
  }

  function safeTransferETH(address to, uint256 value) internal {
    // solhint-disable-next-line no-call-value
    (bool success, ) = to.call{ value: value }(new bytes(0));
    require(success, "!safeTransferETH");
  }

  function isContract(IERC20 account) internal view returns (bool) {
    // This method relies on extcodesize, which returns 0 for contracts in
    // construction, since the code is only stored at the end of the
    // constructor execution.

    uint256 size;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }
}
