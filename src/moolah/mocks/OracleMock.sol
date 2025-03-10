// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import { IOracle } from "../interfaces/IOracle.sol";

contract OracleMock is IOracle {
  mapping(address => uint256) public price;

  function peek(address asset) external view returns (uint256) {
    return price[asset];
  }

  function setPrice(address asset, uint256 newPrice) external {
    price[asset] = newPrice;
  }
}
