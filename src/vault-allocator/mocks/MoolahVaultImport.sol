// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;
// Force foundry to compile MoolahVault even though it's not imported by the public allocator or by the tests.
// MoolahVault will be compiled with its own solidity version.
// The resulting bytecode is then loaded by the tests.

import "moolahvault/MoolahVault.sol";
