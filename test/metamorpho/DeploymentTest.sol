// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./helpers/IntegrationTest.sol";

contract DeploymentTest is IntegrationTest {
  function testDeployMetaMorphoAddresssZero() public {
    vm.expectRevert(ErrorsLib.ZeroAddress.selector);
    new MetaMorpho(address(0), address(loanToken));
  }

  function testDeployMetaMorphoNotToken(address notToken) public {
    vm.assume(address(notToken) != address(loanToken));
    vm.assume(address(notToken) != address(collateralToken));
    vm.assume(address(notToken) != address(vault));

    MetaMorpho metaMorphoImpl = new MetaMorpho(address(morpho), address(loanToken));
    vm.expectRevert();
    new ERC1967Proxy(
      address(metaMorphoImpl),
      abi.encodeWithSelector(
        metaMorphoImpl.initialize.selector,
        OWNER,
        OWNER,
        ConstantsLib.MIN_TIMELOCK,
        notToken,
        "MetaMorpho Vault",
        "MMV"
      )
    );
  }

  function testDeployMetaMorpho(
    address owner,
    address morpho,
    uint256 initialTimelock,
    string memory name,
    string memory symbol
  ) public {
    assumeNotZeroAddress(owner);
    assumeNotZeroAddress(morpho);
    initialTimelock = bound(initialTimelock, ConstantsLib.MIN_TIMELOCK, ConstantsLib.MAX_TIMELOCK);

    IMetaMorpho newVault = createMetaMorpho(owner, morpho, initialTimelock, address(loanToken), name, symbol);

    assertTrue(newVault.hasRole(MANAGER_ROLE, owner), "owner");
    assertEq(address(newVault.MORPHO()), morpho, "morpho");
    assertEq(newVault.timelock(), initialTimelock, "timelock");
    assertEq(newVault.asset(), address(loanToken), "asset");
    assertEq(newVault.name(), name, "name");
    assertEq(newVault.symbol(), symbol, "symbol");
    assertEq(loanToken.allowance(address(newVault), address(morpho)), type(uint256).max, "loanToken allowance");
  }
}
