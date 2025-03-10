// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.24;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { FlowCaps, FlowCapsConfig, Withdrawal, MAX_SETTABLE_FLOW_CAP, IPublicAllocatorStaticTyping, IPublicAllocatorBase } from "./interfaces/IPublicAllocator.sol";
import { Id, IMorpho, IMetaMorpho, MarketAllocation, MarketParams } from "metamorpho/interfaces/IMetaMorpho.sol";
import { Market } from "morpho/interfaces/IMorpho.sol";

import { ErrorsLib } from "./libraries/ErrorsLib.sol";
import { EventsLib } from "./libraries/EventsLib.sol";
import { UtilsLib } from "morpho/libraries/UtilsLib.sol";
import { MarketParamsLib } from "morpho/libraries/MarketParamsLib.sol";
import { MorphoBalancesLib } from "morpho/libraries/periphery/MorphoBalancesLib.sol";

/// @title PublicAllocator
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Publicly callable allocator for MetaMorpho vaults.
contract PublicAllocator is UUPSUpgradeable, AccessControlUpgradeable, IPublicAllocatorStaticTyping {
  using MorphoBalancesLib for IMorpho;
  using MarketParamsLib for MarketParams;
  using UtilsLib for uint256;

  /* CONSTANTS */

  /// @inheritdoc IPublicAllocatorBase
  IMorpho public immutable MORPHO;

  /* STORAGE */

  /// @inheritdoc IPublicAllocatorBase
  mapping(address => address) public admin;
  /// @inheritdoc IPublicAllocatorBase
  mapping(address => uint256) public fee;
  /// @inheritdoc IPublicAllocatorBase
  mapping(address => uint256) public accruedFee;
  /// @inheritdoc IPublicAllocatorStaticTyping
  mapping(address => mapping(Id => FlowCaps)) public flowCaps;

  bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role

  /* MODIFIER */

  /// @dev Reverts if the caller is not the admin nor the owner of this vault.
  modifier onlyAdminOrVaultOwner(address vault) {
    if (msg.sender != admin[vault] && !IMetaMorpho(vault).hasRole(MANAGER, msg.sender)) {
      revert ErrorsLib.NotAdminNorVaultOwner();
    }
    _;
  }

  /* CONSTRUCTOR */

  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @param morpho The address of the Morpho contract.
  constructor(address morpho) {
    require(morpho != address(0), ErrorsLib.ZERO_ADDRESS);
    _disableInitializers();
    MORPHO = IMorpho(morpho);
  }

  /// @dev Initializes the contract.
  /// @param _admin The new admin of the contract.
  /// @param _manager The new manager of the contract.
  function initialize(address _admin, address _manager) public initializer {
    require(_admin != address(0), ErrorsLib.ZERO_ADDRESS);
    require(_manager != address(0), ErrorsLib.ZERO_ADDRESS);

    __AccessControl_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
  }

  /* ADMIN OR VAULT OWNER ONLY */

  /// @inheritdoc IPublicAllocatorBase
  function setAdmin(address vault, address newAdmin) external onlyAdminOrVaultOwner(vault) {
    if (admin[vault] == newAdmin) revert ErrorsLib.AlreadySet();
    admin[vault] = newAdmin;
    emit EventsLib.SetAdmin(msg.sender, vault, newAdmin);
  }

  /// @inheritdoc IPublicAllocatorBase
  function setFee(address vault, uint256 newFee) external onlyAdminOrVaultOwner(vault) {
    if (fee[vault] == newFee) revert ErrorsLib.AlreadySet();
    fee[vault] = newFee;
    emit EventsLib.SetFee(msg.sender, vault, newFee);
  }

  /// @inheritdoc IPublicAllocatorBase
  function setFlowCaps(address vault, FlowCapsConfig[] calldata config) external onlyAdminOrVaultOwner(vault) {
    for (uint256 i = 0; i < config.length; i++) {
      Id id = config[i].id;
      if (!IMetaMorpho(vault).config(id).enabled && (config[i].caps.maxIn > 0 || config[i].caps.maxOut > 0)) {
        revert ErrorsLib.MarketNotEnabled(id);
      }
      if (config[i].caps.maxIn > MAX_SETTABLE_FLOW_CAP || config[i].caps.maxOut > MAX_SETTABLE_FLOW_CAP) {
        revert ErrorsLib.MaxSettableFlowCapExceeded();
      }
      flowCaps[vault][id] = config[i].caps;
    }

    emit EventsLib.SetFlowCaps(msg.sender, vault, config);
  }

  /// @inheritdoc IPublicAllocatorBase
  function transferFee(address vault, address payable feeRecipient) external onlyAdminOrVaultOwner(vault) {
    uint256 claimed = accruedFee[vault];
    accruedFee[vault] = 0;
    feeRecipient.transfer(claimed);
    emit EventsLib.TransferFee(msg.sender, vault, claimed, feeRecipient);
  }

  /* PUBLIC */

  /// @inheritdoc IPublicAllocatorBase
  function reallocateTo(
    address vault,
    Withdrawal[] calldata withdrawals,
    MarketParams calldata supplyMarketParams
  ) external payable {
    if (msg.value != fee[vault]) revert ErrorsLib.IncorrectFee();
    if (msg.value > 0) accruedFee[vault] += msg.value;

    if (withdrawals.length == 0) revert ErrorsLib.EmptyWithdrawals();

    Id supplyMarketId = supplyMarketParams.id();
    if (!IMetaMorpho(vault).config(supplyMarketId).enabled) revert ErrorsLib.MarketNotEnabled(supplyMarketId);

    MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length + 1);
    uint128 totalWithdrawn;

    Id id;
    Id prevId;
    for (uint256 i = 0; i < withdrawals.length; i++) {
      prevId = id;
      id = withdrawals[i].marketParams.id();
      if (!IMetaMorpho(vault).config(id).enabled) revert ErrorsLib.MarketNotEnabled(id);
      uint128 withdrawnAssets = withdrawals[i].amount;
      if (withdrawnAssets == 0) revert ErrorsLib.WithdrawZero(id);

      if (Id.unwrap(id) <= Id.unwrap(prevId)) revert ErrorsLib.InconsistentWithdrawals();
      if (Id.unwrap(id) == Id.unwrap(supplyMarketId)) revert ErrorsLib.DepositMarketInWithdrawals();

      MORPHO.accrueInterest(withdrawals[i].marketParams);
      uint256 assets = MORPHO.expectedSupplyAssets(withdrawals[i].marketParams, address(vault));

      if (flowCaps[vault][id].maxOut < withdrawnAssets) revert ErrorsLib.MaxOutflowExceeded(id);
      if (assets < withdrawnAssets) revert ErrorsLib.NotEnoughSupply(id);

      flowCaps[vault][id].maxIn += withdrawnAssets;
      flowCaps[vault][id].maxOut -= withdrawnAssets;
      allocations[i].marketParams = withdrawals[i].marketParams;
      allocations[i].assets = assets - withdrawnAssets;

      totalWithdrawn += withdrawnAssets;

      emit EventsLib.PublicWithdrawal(msg.sender, vault, id, withdrawnAssets);
    }

    if (flowCaps[vault][supplyMarketId].maxIn < totalWithdrawn) revert ErrorsLib.MaxInflowExceeded(supplyMarketId);

    flowCaps[vault][supplyMarketId].maxIn -= totalWithdrawn;
    flowCaps[vault][supplyMarketId].maxOut += totalWithdrawn;
    allocations[withdrawals.length].marketParams = supplyMarketParams;
    allocations[withdrawals.length].assets = type(uint256).max;

    IMetaMorpho(vault).reallocate(allocations);

    emit EventsLib.PublicReallocateTo(msg.sender, vault, supplyMarketId, totalWithdrawn);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
