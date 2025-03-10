// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IOracle
/// @author Lista
/// @notice Interface that oracles used by Lista must implement.
/// @dev It is the user's responsibility to select markets with safe oracles.
interface IOracle {
  function peek(address asset) external view returns (uint256);
}
