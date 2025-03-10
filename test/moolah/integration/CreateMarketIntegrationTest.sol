// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

contract CreateMarketIntegrationTest is BaseTest {
  using MathLib for uint256;
  using MarketParamsLib for MarketParams;

  function testCreateMarketWithNotEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
    vm.assume(!moolah.isIrmEnabled(marketParamsFuzz.irm) && !moolah.isLltvEnabled(marketParamsFuzz.lltv));

    vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);
  }

  function testCreateMarketWithNotEnabledIrmAndEnabledLltv(MarketParams memory marketParamsFuzz) public {
    vm.assume(!moolah.isIrmEnabled(marketParamsFuzz.irm));

    vm.expectRevert(bytes(ErrorsLib.IRM_NOT_ENABLED));
    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);
  }

  function testCreateMarketWithEnabledIrmAndNotEnabledLltv(MarketParams memory marketParamsFuzz) public {
    vm.assume(!moolah.isLltvEnabled(marketParamsFuzz.lltv));

    vm.startPrank(OWNER);
    if (!moolah.isIrmEnabled(marketParamsFuzz.irm)) moolah.enableIrm(marketParamsFuzz.irm);
    vm.stopPrank();

    vm.expectRevert(bytes(ErrorsLib.LLTV_NOT_ENABLED));
    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);
  }

  function testCreateMarketWithEnabledIrmAndLltv(MarketParams memory marketParamsFuzz) public {
    marketParamsFuzz.irm = address(irm);
    marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);
    Id marketParamsFuzzId = marketParamsFuzz.id();

    vm.startPrank(OWNER);
    if (!moolah.isLltvEnabled(marketParamsFuzz.lltv)) moolah.enableLltv(marketParamsFuzz.lltv);
    vm.stopPrank();

    vm.expectEmit(true, true, true, true, address(moolah));
    emit EventsLib.CreateMarket(marketParamsFuzz.id(), marketParamsFuzz);
    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);

    assertEq(moolah.market(marketParamsFuzzId).lastUpdate, block.timestamp, "lastUpdate != block.timestamp");
    assertEq(moolah.market(marketParamsFuzzId).totalSupplyAssets, 0, "totalSupplyAssets != 0");
    assertEq(moolah.market(marketParamsFuzzId).totalSupplyShares, 0, "totalSupplyShares != 0");
    assertEq(moolah.market(marketParamsFuzzId).totalBorrowAssets, 0, "totalBorrowAssets != 0");
    assertEq(moolah.market(marketParamsFuzzId).totalBorrowShares, 0, "totalBorrowShares != 0");
    assertEq(moolah.market(marketParamsFuzzId).fee, 0, "fee != 0");
  }

  function testCreateMarketAlreadyCreated(MarketParams memory marketParamsFuzz) public {
    marketParamsFuzz.irm = address(irm);
    marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);

    vm.startPrank(OWNER);
    if (!moolah.isLltvEnabled(marketParamsFuzz.lltv)) moolah.enableLltv(marketParamsFuzz.lltv);
    vm.stopPrank();

    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);

    vm.expectRevert(bytes(ErrorsLib.MARKET_ALREADY_CREATED));
    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);
  }

  function testIdToMarketParams(MarketParams memory marketParamsFuzz) public {
    marketParamsFuzz.irm = address(irm);
    marketParamsFuzz.lltv = _boundValidLltv(marketParamsFuzz.lltv);
    Id marketParamsFuzzId = marketParamsFuzz.id();

    vm.startPrank(OWNER);
    if (!moolah.isLltvEnabled(marketParamsFuzz.lltv)) moolah.enableLltv(marketParamsFuzz.lltv);
    vm.stopPrank();

    vm.prank(OWNER);
    moolah.createMarket(marketParamsFuzz);

    MarketParams memory params = moolah.idToMarketParams(marketParamsFuzzId);

    assertEq(marketParamsFuzz.loanToken, params.loanToken, "loanToken != loanToken");
    assertEq(marketParamsFuzz.collateralToken, params.collateralToken, "collateralToken != collateralToken");
    assertEq(marketParamsFuzz.irm, params.irm, "irm != irm");
    assertEq(marketParamsFuzz.lltv, params.lltv, "lltv != lltv");
  }
}
