pragma solidity ^0.8.13;
import "./Interface.sol";

interface ILiquidator {
  struct MoolahLiquidateData {
    address collateralToken;
    address loanToken;
    uint256 seized;
    address pair;
    bytes swapData;
  }
  function withdrawETH(uint256 amount) external;
  function withdrawERC20(address token, uint256 amount) external;
  function approveERC20(address token, address to, uint256 amount) external;
  function moolahLiquidate(
    bytes32 id,
    address borrower,
    uint256 seizedAssets,
    address pair,
    bytes calldata swapData
  ) external payable;
}
