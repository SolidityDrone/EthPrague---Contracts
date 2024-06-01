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

contract CaptainHappyHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    uint public currentBlock;
    address[] public traderAddressesInThisBlockAtoB;
    int[] public tradeAmountsInThisBlockAtoB;
    address[] public traderAddressesInThisBlockBtoA;
    int[] public tradeAmountsInThisBlockBtoA;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // TEMPORARY LOCATION FOR THIS FUNCTION - WILL GO IN CHAINLINK AUTOMATION
    // function sortTrades() takes TradesPerBlock as argument, then for each of the two lists
    // function sortTrades()

    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        if (block.number != currentBlock) {
            currentBlock = block.number;
            if (params.zeroForOne) {
                traderAddressesInThisBlockAtoB = [msg.sender];
                tradeAmountsInThisBlockAtoB = [params.amountSpecified];
            } else {
                traderAddressesInThisBlockBtoA = [msg.sender];
                tradeAmountsInThisBlockBtoA = [params.amountSpecified];
            }
        } else {
            if (params.zeroForOne) {
                traderAddressesInThisBlockAtoB.push(msg.sender);
                tradeAmountsInThisBlockAtoB.push(params.amountSpecified);
            } else {
                traderAddressesInThisBlockBtoA.push(msg.sender);
                tradeAmountsInThisBlockBtoA.push(params.amountSpecified);
            }
        }

        // All txs are NoOp, so we return the amount that's taken by the hook https://www.v4-by-example.org/hooks/no-op
        int _swapDelta = params.zeroForOne
            ? params.amountSpecified
            : -params.amountSpecified;
        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(_swapDelta), 0),
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
                beforeRemoveLiquidity: true, // -- No-op'ing the swap --  //
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
