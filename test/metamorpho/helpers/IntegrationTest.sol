// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant TIMELOCK = 1 weeks;

contract IntegrationTest is BaseTest {
  using MathLib for uint256;
  using MorphoBalancesLib for IMorpho;
  using MarketParamsLib for MarketParams;

  IMetaMorpho internal vault;

  function setUp() public virtual override {
    super.setUp();

    vault = createMetaMorpho(OWNER, address(morpho), TIMELOCK, address(loanToken), "MetaMorpho Vault", "MMV");

    vm.startPrank(OWNER);
    vault.setCurator(CURATOR_ADDR);
    vault.setIsAllocator(ALLOCATOR_ADDR, true);
    vault.setFeeRecipient(FEE_RECIPIENT);
    vault.setSkimRecipient(SKIM_RECIPIENT);
    vm.stopPrank();

    _setCap(idleParams, type(uint184).max);

    loanToken.approve(address(vault), type(uint256).max);
    collateralToken.approve(address(vault), type(uint256).max);

    vm.startPrank(SUPPLIER);
    loanToken.approve(address(vault), type(uint256).max);
    collateralToken.approve(address(vault), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(ONBEHALF);
    loanToken.approve(address(vault), type(uint256).max);
    collateralToken.approve(address(vault), type(uint256).max);
    vm.stopPrank();
  }

  // Deploy MetaMorpho from artifacts
  // Replaces using `new MetaMorpho` which would force 0.8.21 on all tests
  // (since MetaMorpho has pragma solidity 0.8.21)
  function createMetaMorpho(
    address owner,
    address morpho,
    uint256 initialTimelock,
    address asset,
    string memory name,
    string memory symbol
  ) public returns (IMetaMorpho) {
    return newMetaMorpho(owner, owner, morpho, initialTimelock, asset, name, symbol);
  }

  function _idle() internal view returns (uint256) {
    return morpho.expectedSupplyAssets(idleParams, address(vault));
  }

  function _setTimelock(uint256 newTimelock) internal {
    uint256 timelock = vault.timelock();
    if (newTimelock == timelock) return;

    // block.timestamp defaults to 1 which may lead to an unrealistic state: block.timestamp < timelock.
    if (block.timestamp < timelock) vm.warp(block.timestamp + timelock);

    PendingUint192 memory pendingTimelock = vault.pendingTimelock();
    if (pendingTimelock.validAt == 0 || newTimelock != pendingTimelock.value) {
      vm.prank(OWNER);
      vault.submitTimelock(newTimelock);
    }

    if (newTimelock > timelock) return;

    vm.warp(block.timestamp + timelock);

    vault.acceptTimelock();

    assertEq(vault.timelock(), newTimelock, "_setTimelock");
  }

  function _setGuardian(address newGuardian) internal {
    if (vault.hasRole(GUARDIAN_ROLE, newGuardian)) return;

    PendingAddress memory pendingGuardian = vault.pendingGuardian();
    if (pendingGuardian.validAt == 0 || newGuardian != pendingGuardian.value) {
      vm.prank(OWNER);
      vault.submitGuardian(newGuardian);
    }

    vm.warp(block.timestamp + vault.timelock());

    vault.acceptGuardian();

    assertTrue(vault.hasRole(GUARDIAN_ROLE, newGuardian), "_setGuardian");
  }

  function _setFee(uint256 newFee) internal {
    uint256 fee = vault.fee();
    if (newFee == fee) return;

    vm.prank(OWNER);
    vault.setFee(newFee);

    assertEq(vault.fee(), newFee, "_setFee");
  }

  function _setCap(MarketParams memory marketParams, uint256 newCap) internal {
    Id id = marketParams.id();
    uint256 cap = vault.config(id).cap;
    bool isEnabled = vault.config(id).enabled;
    if (newCap == cap) return;

    PendingUint192 memory pendingCap = vault.pendingCap(id);
    if (pendingCap.validAt == 0 || newCap != pendingCap.value) {
      vm.prank(CURATOR_ADDR);
      vault.submitCap(marketParams, newCap);
    }

    if (newCap < cap) return;

    vm.warp(block.timestamp + vault.timelock());

    vault.acceptCap(marketParams);

    assertEq(vault.config(id).cap, newCap, "_setCap");

    if (newCap > 0) {
      if (!isEnabled) {
        Id[] memory newSupplyQueue = new Id[](vault.supplyQueueLength() + 1);
        for (uint256 k; k < vault.supplyQueueLength(); k++) {
          newSupplyQueue[k] = vault.supplyQueue(k);
        }
        newSupplyQueue[vault.supplyQueueLength()] = id;
        vm.prank(ALLOCATOR_ADDR);
        vault.setSupplyQueue(newSupplyQueue);
      }
    }
  }

  function _sortSupplyQueueIdleLast() internal {
    Id[] memory supplyQueue = new Id[](vault.supplyQueueLength());

    uint256 supplyIndex;
    for (uint256 i; i < supplyQueue.length; ++i) {
      Id id = vault.supplyQueue(i);
      if (Id.unwrap(id) == Id.unwrap(idleParams.id())) continue;

      supplyQueue[supplyIndex] = id;
      ++supplyIndex;
    }

    supplyQueue[supplyIndex] = idleParams.id();
    ++supplyIndex;

    assembly {
      mstore(supplyQueue, supplyIndex)
    }

    vm.prank(ALLOCATOR_ADDR);
    vault.setSupplyQueue(supplyQueue);
  }
}
