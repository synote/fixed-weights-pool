// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";

library WeightMath {
    using FixedPointMathLib for *;
    using SafeCastLib for *;

    function calcInvariant(
        uint256 rX,
        uint256 rY,
        uint256 weightX,
        uint256 weightY
    ) internal pure returns (uint256 invariant) {
        //
        // rX^wX
        // rY^wY
        //
        invariant = 1e18.mulWad(powWad(rX, weightX)).mulWad(
            powWad(rY, weightY)
        );
    }

    function calcAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 weightIn,
        uint256 weightOut
    ) internal pure returns (uint256) {
        // -----------------------------------------------------------------------
        //
        //             ⎛                          ⎛weightIn ⎞⎞
        //             ⎜                           ─────────  ⎟
        //             ⎜                          ⎝weightOut⎠⎟
        //             ⎜    ⎛      reserveIn     ⎞           ⎟
        // reserveOut ⋅  1 -  ────────────────────
        //             ⎝    ⎝reserveIn + amountIn⎠           ⎠
        // -----------------------------------------------------------------------

        return reserveOut.mulWad(
            1e18.rawSub(
                powWadUp(
                    reserveIn.divWadUp(reserveIn + amountIn),
                    weightIn.divWad(weightOut)
                )
            )
        );
    }

    function calcAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 weightIn,
        uint256 weightOut
    ) internal pure returns (uint256) {
        // -----------------------------------------------------------------------
        //
        //             ⎛                       ⎛weightIn ⎞    ⎞
        //             ⎜                        ─────────      ⎟
        //             ⎜                       ⎝weightOut⎠    ⎟
        //             ⎜⎛     reserveOut      ⎞               ⎟
        // reserveIn ⋅    ─────────────────────             - 1
        //             ⎝⎝reserveOut - amountIn⎠               ⎠
        // -----------------------------------------------------------------------

        return reserveIn.mulWadUp(
            powWadUp(
                reserveOut.divWadUp(reserveOut.rawSub(amountOut)),
                weightOut.divWadUp(weightIn)
            ) - 1 ether
        );
    }
}