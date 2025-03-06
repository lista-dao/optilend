// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract RoleManagerIntegrationTest is BaseTest {
  using MathLib for uint256;

  function testDeployWithAddressZero() public {
    Morpho morphoImpl = new Morpho();

    vm.expectRevert(bytes(ErrorsLib.ZERO_ADDRESS));
    new ERC1967Proxy(
      address(morphoImpl),
      abi.encodeWithSelector(morphoImpl.initialize.selector, address(0), address(0))
    );
  }

  function testGrantRoleWhenNotAdmin(address addressFuzz) public {
    vm.assume(addressFuzz != OWNER);

    vm.prank(addressFuzz);

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, addressFuzz, DEFAULT_ADMIN_ROLE)
    );
    Morpho(address(morpho)).grantRole(MANAGER, addressFuzz);
  }

  function testGrantRole(address newOwner) public {
    vm.assume(newOwner != OWNER);

    vm.startPrank(OWNER);
    vm.expectEmit(true, true, true, true, address(morpho));
    emit IAccessControl.RoleGranted(MANAGER, newOwner, OWNER);
    Morpho(address(morpho)).grantRole(MANAGER, newOwner);
    vm.stopPrank();

    assertTrue(Morpho(address(morpho)).hasRole(MANAGER, newOwner), "owner is not set");
  }

  function testEnableIrmWhenNotOwner(address addressFuzz, address irmFuzz) public {
    vm.assume(addressFuzz != OWNER);
    vm.assume(irmFuzz != address(irm));

    vm.prank(addressFuzz);
    vm.expectRevert(bytes(ErrorsLib.NOT_MANAGER));
    morpho.enableIrm(irmFuzz);
  }

  function testEnableIrmAlreadySet() public {
    vm.prank(OWNER);
    vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
    morpho.enableIrm(address(irm));
  }

  function testEnableIrm(address irmFuzz) public {
    vm.assume(!morpho.isIrmEnabled(irmFuzz));

    vm.prank(OWNER);
    vm.expectEmit(true, true, true, true, address(morpho));
    emit EventsLib.EnableIrm(irmFuzz);
    morpho.enableIrm(irmFuzz);

    assertTrue(morpho.isIrmEnabled(irmFuzz), "IRM is not enabled");
  }

  function testEnableLltvWhenNotOwner(address addressFuzz, uint256 lltvFuzz) public {
    vm.assume(addressFuzz != OWNER);
    vm.assume(lltvFuzz != marketParams.lltv);

    vm.prank(addressFuzz);
    vm.expectRevert(bytes(ErrorsLib.NOT_MANAGER));
    morpho.enableLltv(lltvFuzz);
  }

  function testEnableLltvAlreadySet() public {
    vm.prank(OWNER);
    vm.expectRevert(bytes(ErrorsLib.ALREADY_SET));
    morpho.enableLltv(marketParams.lltv);
  }

  function testEnableTooHighLltv(uint256 lltv) public {
    lltv = bound(lltv, WAD, type(uint256).max);

    vm.prank(OWNER);
    vm.expectRevert(bytes(ErrorsLib.MAX_LLTV_EXCEEDED));
    morpho.enableLltv(lltv);
  }

  function testEnableLltv(uint256 lltvFuzz) public {
    lltvFuzz = _boundValidLltv(lltvFuzz);

    vm.assume(!morpho.isLltvEnabled(lltvFuzz));

    vm.prank(OWNER);
    vm.expectEmit(true, true, true, true, address(morpho));
    emit EventsLib.EnableLltv(lltvFuzz);
    morpho.enableLltv(lltvFuzz);

    assertTrue(morpho.isLltvEnabled(lltvFuzz), "LLTV is not enabled");
  }

  function testSetFeeWhenNotOwner(address addressFuzz, uint256 feeFuzz) public {
    vm.assume(addressFuzz != OWNER);

    vm.prank(addressFuzz);
    vm.expectRevert(bytes(ErrorsLib.NOT_MANAGER));
    morpho.setFee(marketParams, feeFuzz);
  }

  function testSetFeeWhenMarketNotCreated(MarketParams memory marketParamsFuzz, uint256 feeFuzz) public {
    vm.assume(neq(marketParamsFuzz, marketParams));

    vm.prank(OWNER);
    vm.expectRevert(bytes(ErrorsLib.MARKET_NOT_CREATED));
    morpho.setFee(marketParamsFuzz, feeFuzz);
  }

  function testSetTooHighFee(uint256 feeFuzz) public {
    feeFuzz = bound(feeFuzz, MAX_FEE + 1, type(uint256).max);

    vm.prank(OWNER);
    vm.expectRevert(bytes(ErrorsLib.MAX_FEE_EXCEEDED));
    morpho.setFee(marketParams, feeFuzz);
  }

  function testSetFee(uint256 feeFuzz) public {
    feeFuzz = bound(feeFuzz, 1, MAX_FEE);

    vm.prank(OWNER);
    vm.expectEmit(true, true, true, true, address(morpho));
    emit EventsLib.SetFee(id, feeFuzz);
    morpho.setFee(marketParams, feeFuzz);

    assertEq(morpho.market(id).fee, feeFuzz);
  }

  function testSetFeeRecipientWhenNotOwner(address addressFuzz) public {
    vm.assume(addressFuzz != OWNER);

    vm.prank(addressFuzz);
    vm.expectRevert(bytes(ErrorsLib.NOT_MANAGER));
    morpho.setFeeRecipient(addressFuzz);
  }

  function testSetFeeRecipient(address newFeeRecipient) public {
    vm.assume(newFeeRecipient != morpho.feeRecipient());

    vm.prank(OWNER);
    vm.expectEmit(true, true, true, true, address(morpho));
    emit EventsLib.SetFeeRecipient(newFeeRecipient);
    morpho.setFeeRecipient(newFeeRecipient);

    assertEq(morpho.feeRecipient(), newFeeRecipient);
  }
}
