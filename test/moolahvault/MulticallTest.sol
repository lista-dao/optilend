// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";

contract MulticallTest is IntegrationTest {
  bytes[] internal data;

  function testMulticall() public {
    data.push(abi.encodeCall(IMoolahVaultBase.setCurator, (address(1))));
    data.push(abi.encodeCall(IMoolahVaultBase.setIsAllocator, (address(1), true)));
    data.push(abi.encodeCall(IMoolahVaultBase.submitTimelock, (ConstantsLib.MAX_TIMELOCK)));

    vm.prank(OWNER);
    vault.multicall(data);

    assertTrue(vault.hasRole(CURATOR_ROLE, address(1)));
    assertTrue(vault.hasRole(ALLOCATOR_ROLE, address(1)));
    assertEq(vault.timelock(), ConstantsLib.MAX_TIMELOCK);
  }
}
