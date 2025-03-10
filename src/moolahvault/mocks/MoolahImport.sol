// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;
// Force foundry to compile Moolah even though it's not imported by MoolahVault or by the tests.
// Moolah will be compiled with its own solidity version.
// The resulting bytecode is then loaded by BaseTest.sol.

import "moolah/Moolah.sol";
