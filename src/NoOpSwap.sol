// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

contract NoOpSwap is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    mapping(PoolId => uint256 count) public beforeSwapCount;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        // -------------------------------------------------------------------------------------------- //
        // Example NoOp: if swap is exactInput and the amount is 69e18, then the swap will be skipped   //
        // -------------------------------------------------------------------------------------------- //
        if (params.amountSpecified == -69e18) {
            // take the input token so that v3-swap is skipped...
            uint256 amountTaken = 69e18;
            Currency input = params.zeroForOne ? key.currency0 : key.currency1;
            poolManager.mint(address(this), input.toId(), amountTaken);

            // to NoOp the exact input, we return the amount that's taken by the hook
            return (
                BaseHook.beforeSwap.selector,
                toBeforeSwapDelta(amountTaken.toInt128(), 0),
                0
            );
        }

        beforeSwapCount[key.toId()]++;
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external virtual override returns (bytes4) {
        revert HookNotImplemented();
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: true,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // -- No-op'ing the swap --  //
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // -- No-op'ing the swap --  //
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }
}
