// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MathLib, WAD_INT } from "interest-rate-model/libraries/MathLib.sol";
import { ExpLib } from "interest-rate-model/libraries/ExpLib.sol";
import { ConstantsLib } from "interest-rate-model/libraries/ConstantsLib.sol";
import { MathLib as MoolahMathLib } from "moolah/libraries/MathLib.sol";

import "forge-std/Test.sol";

contract ExpLibTest is Test {
  using MathLib for int256;
  using MoolahMathLib for uint256;

  /// @dev ln(1e-9) truncated at 2 decimal places.
  int256 internal constant LN_GWEI_INT = -20.72 ether;

  function testWExp(int256 x) public pure {
    // Bounded to have sub-1% relative error.
    x = bound(x, LN_GWEI_INT, ExpLib.WEXP_UPPER_BOUND);

    assertApproxEqRel(ExpLib.wExp(x), wadExp(x), 0.01 ether);
  }

  function testWExpSmall(int256 x) public pure {
    x = bound(x, ExpLib.LN_WEI_INT, LN_GWEI_INT);

    assertApproxEqAbs(ExpLib.wExp(x), 0, 1e10);
  }

  function testWExpTooSmall(int256 x) public pure {
    x = bound(x, type(int256).min, ExpLib.LN_WEI_INT);

    assertEq(ExpLib.wExp(x), 0);
  }

  function testWExpTooLarge(int256 x) public pure {
    x = bound(x, ExpLib.WEXP_UPPER_BOUND, type(int256).max);

    assertEq(ExpLib.wExp(x), ExpLib.WEXP_UPPER_VALUE);
  }

  function testWExpDoesNotLeadToOverflow() public pure {
    assertGt(ExpLib.WEXP_UPPER_VALUE * 1e18, 0);
  }

  function testWExpContinuousUpperBound() public pure {
    assertApproxEqRel(ExpLib.wExp(ExpLib.WEXP_UPPER_BOUND - 1), ExpLib.WEXP_UPPER_VALUE, 1e-10 ether);
    assertEq(_wExpUnbounded(ExpLib.WEXP_UPPER_BOUND), ExpLib.WEXP_UPPER_VALUE);
  }

  function testWExpPositive(int256 x) public pure {
    x = bound(x, 0, type(int256).max);

    assertGe(ExpLib.wExp(x), 1e18);
  }

  function testWExpNegative(int256 x) public pure {
    x = bound(x, type(int256).min, 0);

    assertLe(ExpLib.wExp(x), 1e18);
  }

  function testWExpWMulMaxRate() public pure {
    ExpLib.wExp(ExpLib.WEXP_UPPER_BOUND).wMulToZero(ConstantsLib.MAX_RATE_AT_TARGET);
  }

  function _wExpUnbounded(int256 x) internal pure returns (int256) {
    unchecked {
      // Decompose x as x = q * ln(2) + r with q an integer and -ln(2)/2 <= r <= ln(2)/2.
      // q = x / ln(2) rounded half toward zero.
      int256 roundingAdjustment = (x < 0) ? -(ExpLib.LN_2_INT / 2) : (ExpLib.LN_2_INT / 2);
      // Safe unchecked because x is bounded.
      int256 q = (x + roundingAdjustment) / ExpLib.LN_2_INT;
      // Safe unchecked because |q * ln(2) - x| <= ln(2)/2.
      int256 r = x - q * ExpLib.LN_2_INT;

      // Compute e^r with a 2nd-order Taylor polynomial.
      // Safe unchecked because |r| < 1e18.
      int256 expR = WAD_INT + r + (r * r) / WAD_INT / 2;

      // Return e^x = 2^q * e^r.
      if (q >= 0) return expR << uint256(q);
      else return expR >> uint256(-q);
    }
  }

  function wadExp(int256 x) internal pure returns (int256 r) {
    unchecked {
      // When the result is < 0.5 we return zero. This happens when
      // x <= floor(log(0.5e18) * 1e18) ~ -42e18
      if (x <= -42139678854452767551) return 0;

      // When the result is > (2**255 - 1) / 1e18 we can not represent it as an
      // int. This happens when x >= floor(log((2**255 - 1) / 1e18) * 1e18) ~ 135.
      if (x >= 135305999368893231589) revert("EXP_OVERFLOW");

      // x is now in the range (-42, 136) * 1e18. Convert to (-42, 136) * 2**96
      // for more intermediate precision and a binary basis. This base conversion
      // is a multiplication by 1e18 / 2**96 = 5**18 / 2**78.
      x = (x << 78) / 5 ** 18;

      // Reduce range of x to (-½ ln 2, ½ ln 2) * 2**96 by factoring out powers
      // of two such that exp(x) = exp(x') * 2**k, where k is an integer.
      // Solving this gives k = round(x / log(2)) and x' = x - k * log(2).
      int256 k = ((x << 96) / 54916777467707473351141471128 + 2 ** 95) >> 96;
      x = x - k * 54916777467707473351141471128;

      // k is in the range [-61, 195].

      // Evaluate using a (6, 7)-term rational approximation.
      // p is made monic, we'll multiply by a scale factor later.
      int256 y = x + 1346386616545796478920950773328;
      y = ((y * x) >> 96) + 57155421227552351082224309758442;
      int256 p = y + x - 94201549194550492254356042504812;
      p = ((p * y) >> 96) + 28719021644029726153956944680412240;
      p = p * x + (4385272521454847904659076985693276 << 96);

      // We leave p in 2**192 basis so we don't need to scale it back up for the division.
      int256 q = x - 2855989394907223263936484059900;
      q = ((q * x) >> 96) + 50020603652535783019961831881945;
      q = ((q * x) >> 96) - 533845033583426703283633433725380;
      q = ((q * x) >> 96) + 3604857256930695427073651918091429;
      q = ((q * x) >> 96) - 14423608567350463180887372962807573;
      q = ((q * x) >> 96) + 26449188498355588339934803723976023;

      /// @solidity memory-safe-assembly
      assembly {
        // Div in assembly because solidity adds a zero check despite the unchecked.
        // The q polynomial won't have zeros in the domain as all its roots are complex.
        // No scaling is necessary because p is already 2**96 too large.
        r := sdiv(p, q)
      }

      // r should be in the range (0.09, 0.25) * 2**96.

      // We now need to multiply r by:
      // * the scale factor s = ~6.031367120.
      // * the 2**k factor from the range reduction.
      // * the 1e18 / 2**96 factor for base conversion.
      // We do this all at once, with an intermediate result in 2**213
      // basis, so the final right shift is always by a positive amount.
      r = int256((uint256(r) * 3822833074963236453042738258902158003155416615667) >> uint256(195 - k));
    }
  }
}
