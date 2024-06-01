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

    address[] public traderAddressesInThisBlockAtoB;
    address[] public traderAddressesInThisBlockBtoA;
    uint[] public tradeAmountsInThisBlockAtoB;
    uint[] public tradeAmountsInThisBlockBtoA;
    uint public currentBlock;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // TEMPORARY LOCATION FOR tradeSort & tradeMerge - WILL GO IN CHAINLINK AUTOMATION

    function tradeSort(
        uint[] memory arr,
        address[] memory addrArr,
        int left,
        int right
    ) public pure returns (uint[] memory, address[] memory) {
        int i = left;
        int j = right;
        if (i != j) {
            uint pivot = arr[uint(left + (right - left) / 2)];
            while (i <= j) {
                while (arr[uint(i)] > pivot) i++;
                while (pivot > arr[uint(j)]) j--;
                if (i <= j) {
                    (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                    (addrArr[uint(i)], addrArr[uint(j)]) = (
                        addrArr[uint(j)],
                        addrArr[uint(i)]
                    );
                    i++;
                    j--;
                }
            }
            if (left < j) tradeSort(arr, addrArr, left, j);
            if (i < right) tradeSort(arr, addrArr, i, right);
        }
        return (arr, addrArr);
    }

    function tradeMerge(
        uint[] memory descendingAmountsAtoB,
        uint[] memory descendingAmountsBtoA,
        address[] memory descendingAddressesAtoB,
        address[] memory descendingAddressesBtoA
    ) public pure returns (uint[] memory, address[] memory) {
        // set a midpoint demand offset to minimise price impact
        uint demandOffset = 0;
        for (uint256 i = 0; i < descendingAmountsAtoB.length; i++) {
            demandOffset += descendingAmountsAtoB[i];
        }
        for (uint256 i = 0; i < descendingAmountsBtoA.length; i++) {
            demandOffset -= descendingAmountsBtoA[i];
        }

        // merge amounts and addresses to aim for a zero demand offset
        uint totalTradeCount = descendingAmountsAtoB.length +
            descendingAmountsBtoA.length;
        uint[] memory mergedAmounts = new uint[](totalTradeCount);
        address[] memory mergedAddresses;
        uint tradesProcessed = 0;
        uint elementsAToB;
        uint elementsBToA;
        while (tradesProcessed < totalTradeCount) {
            elementsAToB = descendingAmountsAtoB.length;
            elementsBToA = descendingAmountsBtoA.length;
            if (demandOffset > 0) {
                for (uint256 i = 0; i < elementsAToB; i++) {
                    mergedAmounts[tradesProcessed] = descendingAmountsAtoB[i];
                    mergedAddresses[tradesProcessed] = descendingAddressesAtoB[
                        i
                    ];
                    demandOffset -= descendingAmountsAtoB[i];
                    tradesProcessed++;
                }
            } else {
                for (uint256 i = 0; i < elementsBToA; i++) {
                    mergedAmounts[tradesProcessed] = descendingAmountsBtoA[i];
                    mergedAddresses[tradesProcessed] = descendingAddressesBtoA[
                        i
                    ];
                    demandOffset += descendingAmountsBtoA[i];
                    tradesProcessed++;
                }
            }
        }
        return (mergedAmounts, mergedAddresses);
    }

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
                tradeAmountsInThisBlockAtoB = [uint(params.amountSpecified)];
            } else {
                traderAddressesInThisBlockBtoA = [msg.sender];
                tradeAmountsInThisBlockBtoA = [uint(params.amountSpecified)];
            }
        } else {
            if (params.zeroForOne) {
                traderAddressesInThisBlockAtoB.push(msg.sender);
                tradeAmountsInThisBlockAtoB.push(uint(params.amountSpecified));
            } else {
                traderAddressesInThisBlockBtoA.push(msg.sender);
                tradeAmountsInThisBlockBtoA.push(uint(params.amountSpecified));
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
