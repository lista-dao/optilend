// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IBot.sol";
import { SafeTransferLib } from "../../lib/solady/src/utils/SafeTransferLib.sol";
import { AccessControlUpgradeable } from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "../../lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

contract Bot is UUPSUpgradeable, AccessControlUpgradeable, IBot {
  /// @dev Thrown when passing the zero address.
  string internal constant ZERO_ADDRESS = "zero address";
  error NoProfit();
  error OnlyAdmin();
  error OnlyManager();
  error OnlyBot();
  error OnlyMorpho();
  address public immutable MORPHO;

  bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role
  bytes32 public constant BOT = keccak256("BOT"); // manager role

  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @param morpho The address of the Morpho contract.
  constructor(address morpho) payable {
    require(morpho != address(0), ZERO_ADDRESS);
    _disableInitializers();
    MORPHO = morpho;
  }

  function initialize(address admin, address manager) public initializer {
    require(admin != address(0), ZERO_ADDRESS);
    require(manager != address(0), ZERO_ADDRESS);
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
    _grantRole(MANAGER, manager);
  }

  receive() external payable {}

  // ------------modifiers----------------
  modifier onlyAdmin() {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert OnlyAdmin();
    _;
  }

  modifier onlyManager() {
    if (!hasRole(MANAGER, msg.sender)) revert OnlyManager();
    _;
  }

  modifier onlyBot() {
    if (!hasRole(BOT, msg.sender)) revert OnlyBot();
    _;
  }

  modifier onlyMorpho() {
    if (msg.sender != address(MORPHO)) revert OnlyMorpho();
    _;
  }

  function withdrawERC20(address token, uint256 amount) external onlyManager {
    SafeTransferLib.safeTransfer(token, msg.sender, amount);
  }

  function withdrawETH(uint256 amount) external onlyManager {
    SafeTransferLib.safeTransferETH(msg.sender, amount);
  }

  function approveERC20(address token, address to, uint256 amount) external onlyManager {
    SafeTransferLib.safeApprove(token, to, amount);
  }

  function morphoLiquidate(
    bytes32 id,
    address borrower,
    uint256 seizedAssets,
    address pair,
    bytes calldata swapData
  ) external payable onlyBot {
    IMorpho.MarketParams memory params = IMorpho(MORPHO).idToMarketParams(id);
    IMorpho(MORPHO).liquidate(
      params,
      borrower,
      seizedAssets,
      0,
      abi.encode(MorphoLiquidateData(params.collateralToken, params.loanToken, seizedAssets, pair, swapData))
    );
  }

  function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external onlyMorpho {
    MorphoLiquidateData memory arb = abi.decode(data, (MorphoLiquidateData));
    (bool success, ) = arb.pair.call(arb.swapData);
    if (!success) revert("swap error");
    uint256 out = SafeTransferLib.balanceOf(arb.loanToken, address(this));
    if (out < repaidAssets) revert NoProfit();
    SafeTransferLib.safeApprove(arb.loanToken, MORPHO, repaidAssets);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
}
