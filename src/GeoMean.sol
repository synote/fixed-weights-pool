// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {WeightMath} from "./WeightMath.sol";

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeCast for *;
    using FullMath for *;

    error SwapNotImplemented();

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;

    // Modify liquidity params for callback function
    struct CallbackData {
        PoolId id;
        uint256 liquidityDelta;
        Currency currency0;
        Currency currency1;
        address sender;
    }


    // Fixed weights for pool reserve
    // The custom pool use defualt 50% : 50% ration for the poc project.
    struct PoolParams {
        uint64 weightX;
        uint64 weightY;
        uint256 reserveX;
        uint256 reserveY;
    }

    mapping(PoolId => PoolParams) public poolWeights;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function getPoolParams(PoolId key)
        public
        view
        returns (uint64, uint64)
    {
        return (poolWeights[key].weightX, poolWeights[key].weightY);
    }

    // Add liquidity directly for weighted pool
    function addLiquidity(PoolKey calldata key, uint256 deltaL) external {
        poolManager.unlock(
            abi.encode(
                CallbackData(
                    key.toId(),
                    deltaL,
                    key.currency0,
                    key.currency1,
                    msg.sender
                )
            )
        );
    }

    function _unlockCallback(
        bytes calldata data
    ) internal override returns (bytes memory) {
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        (uint256 amount0, uint256 amount1) = _getAmountfromDeltaL(
            callbackData.liquidityDelta, poolWeights[callbackData.id]);

        // settle liquidity from sender
        callbackData.currency0.settle(
            poolManager,
            callbackData.sender,
            amount0,
            false
        );
        callbackData.currency1.settle(
            poolManager,
            callbackData.sender,
            amount1,
            false
        );

        // mint claim tokens for the hook
        callbackData.currency0.take(
            poolManager,
            address(this),
            amount0,
            true
        );
        callbackData.currency1.take(
            poolManager,
            address(this),
            amount1,
            true
        );

        return "";
    }

    function _getAmountfromDeltaL(
        uint256 liquidityDelta,
        PoolParams memory pool
        ) internal pure returns (uint256 deltaX, uint256 deltaY) {
        uint256 totalLiquidity = WeightMath.calcInvariant(pool.reserveX, pool.reserveY, 0.5 ether, 0.5 ether);
        deltaX = pool.reserveX.mulDiv(liquidityDelta, totalLiquidity);
        deltaY = pool.reserveY.mulDiv(liquidityDelta, totalLiquidity);
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // convert the amountSpecified to positive
        uint256 amountPositive = params.amountSpecified > 0
            ? uint256(params.amountSpecified)
            : uint256(-params.amountSpecified);

        PoolParams memory wpool = poolWeights[key.toId()];
        BeforeSwapDelta beforeSwapDelta;

        // settle balance to hook
        if (params.zeroForOne) {
            if (params.amountSpecified > 0) {
                // exact output not implemented
                revert SwapNotImplemented();
            }
            // exchange given exact input
            uint256 amountOut = WeightMath.calcAmountOut(
                amountPositive,
                wpool.reserveX,
                wpool.reserveY,
                0.5 ether,
                0.5 ether
            );

            wpool.reserveX += amountPositive;
            wpool.reserveY -= amountOut;
            // mint 6909 claim for hook
            key.currency0.take(
                poolManager,
                address(this),
                amountPositive,
                true
            );

            // burn 6909 claim from hook
            key.currency1.settle(
                poolManager,
                address(this),
                amountOut,
                true
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(-params.amountSpecified),
                -amountOut.toInt128()
            );
        } else {
            if (params.amountSpecified > 0) {
                // exact output not implemented
                revert SwapNotImplemented();
            }
            // exchange given exact input
            uint256 amountOut = WeightMath.calcAmountOut(
                amountPositive,
                wpool.reserveY,
                wpool.reserveX,
                0.5 ether,
                0.5 ether
            );
            // pool reserve changed by swap
            wpool.reserveY += amountPositive;
            wpool.reserveX -= amountOut;
            // mint 6909 claim for hook
            key.currency1.take(
                poolManager,
                address(this),
                amountPositive,
                true
            );
            // burn 6909 claim from hook
            key.currency0.settle(
                poolManager,
                address(this),
                amountOut,
                true
            );

            beforeSwapDelta = toBeforeSwapDelta(
                int128(-params.amountSpecified),
                -amountOut.toInt128()
            );
        }

        beforeSwapCount[key.toId()]++;
        return (BaseHook.beforeSwap.selector, beforeSwapDelta, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        afterSwapCount[key.toId()]++;
        return (BaseHook.afterSwap.selector, 0);
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;
        return BaseHook.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        beforeRemoveLiquidityCount[key.toId()]++;
        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
