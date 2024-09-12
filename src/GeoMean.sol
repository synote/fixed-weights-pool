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
import {ERC6909} from "v4-core/src/ERC6909.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {WeightMath} from "./WeightMath.sol";

contract WeightPool is BaseHook, ERC6909 {
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
        int256 liquidityDelta;
        uint256 maxDeltaX;
        uint256 maxDeltaY;
        Currency currency0;
        Currency currency1;
        address sender;
    }


    // Fixed weights for pool reserve. the weightX weightY is
    // no more than 1 ether which < 100%
    // The custom pool use defualt 50% : 50% ration for the poc project.
    struct PoolReserve {
        uint64 weightX;
        uint64 weightY;
        uint256 reserveX;
        uint256 reserveY;
        uint256 totalLiquidity;
    }

    mapping(PoolId => PoolReserve) public poolWeights;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
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

    function getPoolWeights(PoolId key)
        public
        view
        returns (uint64, uint64)
    {
        return (poolWeights[key].weightX, poolWeights[key].weightY);
    }

    // Add liquidity directly for fixed weight pool
    function addLiquidity(PoolKey calldata key, uint256 deltaL, uint256 maxDeltaX, uint256 maxDeltaY) external {
        poolManager.unlock(
            abi.encode(
                CallbackData(
                    key.toId(),
                    int256(deltaL),
                    maxDeltaX,
                    maxDeltaY,
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
        uint256 amount0;
        uint256 amount1;
        int256 deltaL;
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        if (poolWeights[callbackData.id].reserveX > 0 && poolWeights[callbackData.id].reserveY > 0) {
            (amount0, amount1) = _getAmountfromDeltaL(
                uint256(callbackData.liquidityDelta),
                poolWeights[callbackData.id]
            );
            deltaL = callbackData.liquidityDelta;
        } else {
            // The pool liquidity is not initialized when zero reserve.
            // Here we use max input amount as initial price and reserve.
            // The pool should have a proper way to initialze the price
            // when created at first time.
            amount0 = callbackData.maxDeltaX;
            amount1 = callbackData.maxDeltaY;
            deltaL = int256(WeightMath.calcInvariant(
                amount0,
                amount1,
                poolWeights[callbackData.id].weightX,
                poolWeights[callbackData.id].weightY
            ));
        }

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

        poolWeights[callbackData.id].reserveX += amount0;
        poolWeights[callbackData.id].reserveY += amount1;
        poolWeights[callbackData.id].totalLiquidity += uint256(deltaL);
        _mintShare(callbackData.sender, callbackData.id, uint256(deltaL));

        return "";
    }

    function _increaseLiquidity(
        CallbackData calldata params,
        uint256 amount0,
        uint256 amount1,
        int256 deltaL
        ) internal {
        // settle liquidity from sender
        params.currency0.settle(
            poolManager,
            params.sender,
            amount0,
            false
        );
        params.currency1.settle(
            poolManager,
            params.sender,
            amount1,
            false
        );

        // mint claim tokens for the hook
        params.currency0.take(
            poolManager,
            address(this),
            amount0,
            true
        );
        params.currency1.take(
            poolManager,
            address(this),
            amount1,
            true
        );

        poolWeights[params.id].reserveX += amount0;
        poolWeights[params.id].reserveY += amount1;
        poolWeights[params.id].totalLiquidity += uint256(deltaL);
        _mintShare(params.sender, params.id, uint256(deltaL));
    }

    function _decreaseLiquidity(
        CallbackData calldata params,
        uint256 amount0,
        uint256 amount1,
        int256 deltaL
        ) internal {
        // burn claim tokens for the hook
        params.currency0.settle(
            poolManager,
            address(this),
            amount0,
            true
        );
        params.currency1.settle(
            poolManager,
            address(this),
            amount1,
            true
        );

        // receive currency from manager
        params.currency0.take(
            poolManager,
            params.sender,
            amount0,
            false
        );
        params.currency1.take(
            poolManager,
            params.sender,
            amount1,
            false
        );

        poolWeights[params.id].reserveX -= amount0;
        poolWeights[params.id].reserveY -= amount1;
        poolWeights[params.id].totalLiquidity -= uint256(-deltaL);
        _burnShare(params.sender, params.id, uint256(-deltaL));
    }

    function _getAmountfromDeltaL(
        uint256 liquidityDelta,
        PoolReserve memory pool
        ) internal pure returns (uint256 deltaX, uint256 deltaY) {
        uint256 totalLiquidity = WeightMath.calcInvariant(pool.reserveX, pool.reserveY, pool.weightX, pool.weightY);
        deltaX = pool.reserveX.mulDiv(liquidityDelta, totalLiquidity);
        deltaY = pool.reserveY.mulDiv(liquidityDelta, totalLiquidity);
    }

    function getSpotPrice(PoolKey calldata key)
        public
        view
        returns (uint256) {
        PoolReserve memory pool = poolWeights[key.toId()];
        if (pool.reserveX > 0 && pool.reserveY > 0) {
            return WeightMath.calcSpotPrice(pool.reserveX, pool.reserveY, pool.weightX, pool.weightY);
        } else {
            // uninitialized pool reserves
            return 0;
        }
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        override
        returns (bytes4)
    {
        // The Fixed WeightPool should use the Initialize method to set
        // pool price and reserve weights through hook data. The following
        // code just set the weights to 50% : 50% for poc purpose.
        poolWeights[key.toId()].weightX = 0.5 ether;
        poolWeights[key.toId()].weightY = 0.5 ether;
        return BaseHook.afterInitialize.selector;
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

        PoolReserve memory wpool = poolWeights[key.toId()];
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
                wpool.weightX,
                wpool.weightY
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
                wpool.weightX,
                wpool.weightY
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

    // mint LP token share for address lp
    function _mintShare(address lp, PoolId poolId, uint256 amount) internal {
        _mint(lp, uint256(PoolId.unwrap(poolId)), amount);
    }

    // burn LP token share for address lp
    function _burnShare(address lp, PoolId poolId, uint256 amount) internal {
        _burn(lp, uint256(PoolId.unwrap(poolId)), amount);
    }
}
