// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "./interfaces/IERC20.sol";
import { IMoolah } from "../interfaces/IMoolah.sol";
import { IMoolahFlashLoanCallback } from "../interfaces/IMoolahCallbacks.sol";

contract FlashBorrowerMock is IMoolahFlashLoanCallback {
  IMoolah private immutable MOOLAH;

  constructor(IMoolah newMoolah) {
    MOOLAH = newMoolah;
  }

  function flashLoan(address token, uint256 assets, bytes calldata data) external {
    MOOLAH.flashLoan(token, assets, data);
  }

  function onMoolahFlashLoan(uint256 assets, bytes calldata data) external {
    require(msg.sender == address(MOOLAH));
    address token = abi.decode(data, (address));
    IERC20(token).approve(address(MOOLAH), assets);
  }
}
