// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./ILiquidator.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { IMoolah } from "./ILiquidator.sol";

contract Liquidator is UUPSUpgradeable, AccessControlUpgradeable, ILiquidator {
  /// @dev Thrown when passing the zero address.
  string internal constant ZERO_ADDRESS = "zero address";
  error NoProfit();
  error OnlyAdmin();
  error OnlyManager();
  error OnlyBot();
  error OnlyMoolah();
  address public immutable MOOLAH;

  bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role
  bytes32 public constant BOT = keccak256("BOT"); // manager role

  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @param moolah The address of the Moolah contract.
  constructor(address moolah) payable {
    require(moolah != address(0), ZERO_ADDRESS);
    _disableInitializers();
    MOOLAH = moolah;
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

  modifier onlyMoolah() {
    if (msg.sender != address(MOOLAH)) revert OnlyMoolah();
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

  function moolahLiquidate(
    bytes32 id,
    address borrower,
    uint256 seizedAssets,
    address pair,
    bytes calldata swapData
  ) external payable onlyBot {
    IMoolah.MarketParams memory params = IMoolah(MOOLAH).idToMarketParams(id);
    IMoolah(MOOLAH).liquidate(
      params,
      borrower,
      seizedAssets,
      0,
      abi.encode(MoolahLiquidateData(params.collateralToken, params.loanToken, seizedAssets, pair, swapData))
    );
  }

  function onMoolahLiquidate(uint256 repaidAssets, bytes calldata data) external onlyMoolah {
    MoolahLiquidateData memory arb = abi.decode(data, (MoolahLiquidateData));
    (bool success, ) = arb.pair.call(arb.swapData);
    if (!success) revert("swap error");
    uint256 out = SafeTransferLib.balanceOf(arb.loanToken, address(this));
    if (out < repaidAssets) revert NoProfit();
    SafeTransferLib.safeApprove(arb.loanToken, MOOLAH, repaidAssets);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
}
