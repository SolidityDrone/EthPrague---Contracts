// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {AutomationCompatibleInterface} from "lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";


contract NoOpSwap is BaseHook, AutomationCompatibleInterface {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    uint internal lastFullfilledBlockIndex;
    address internal forwarder;
    address token0 = 0x41Afb4518aD277455C1eF6182F35667949cC0b41;
    address token1 = 0xC0c8C84A1f962Af274Ad3E36Dbb81bAD9B3b969C;
    address poolSwap = 0x841B5A0b3DBc473c8A057E2391014aa4C4751351;
    uint[] blocks;
    mapping(uint => Trade[200]) internal s_tradesInBlock;
    mapping(uint => uint) internal s_blockNonce;
    mapping(uint => bool) internal s_isSavedBlock;

    struct Trade {
        address sender;
        uint amountSpecified;
        bool isZeroToOne;
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // TEMPORARY LOCATION FOR tradeSort & tradeMerge - WILL GO IN CHAINLINK AUTOMATION
    function setForwarder(address _forwarder) external {
        forwarder = _forwarder;
    }

    function tradeSort(
        uint[] memory arr,
        address[] memory addrArr,
        int left,
        int right
    ) internal pure returns (uint[] memory, address[] memory) {
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
    ) public view returns (uint[] memory, address[] memory) {
        // set a midpoint demand offset to minimize price impact
        int demandOffset = 0;
        for (uint256 i = 0; i < descendingAmountsAtoB.length; i++) {
            demandOffset += int(descendingAmountsAtoB[i]);
        }
        for (uint256 i = 0; i < descendingAmountsBtoA.length; i++) {
            demandOffset -= int(descendingAmountsBtoA[i]);
        }

        // merge amounts and addresses to aim for a zero demand offset
        uint totalTradeCount = descendingAmountsAtoB.length + descendingAmountsBtoA.length;
        uint[] memory mergedAmounts = new uint[](totalTradeCount);
        address[] memory mergedAddresses = new address[](totalTradeCount);
        uint tradesProcessed = 0;
        uint iAtoB = 0;
        uint iBtoA = 0;
        
        while (tradesProcessed < totalTradeCount) {
            if (demandOffset > 0 && iAtoB < descendingAmountsAtoB.length) {
                mergedAmounts[tradesProcessed] = descendingAmountsAtoB[iAtoB];
                mergedAddresses[tradesProcessed] = descendingAddressesAtoB[iAtoB];
                demandOffset -= int(descendingAmountsAtoB[iAtoB]);
                iAtoB++;
            } else if (iBtoA < descendingAmountsBtoA.length) {
                mergedAmounts[tradesProcessed] = descendingAmountsBtoA[iBtoA];
                mergedAddresses[tradesProcessed] = descendingAddressesBtoA[iBtoA];
                demandOffset += int(descendingAmountsBtoA[iBtoA]);
                iBtoA++;
            }
            tradesProcessed++;
        }
        return (mergedAmounts, mergedAddresses);
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        if (msg.sender == forwarder) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        if (msg.sender != forwarder) {
            if (!s_isSavedBlock[block.number]) {
                s_isSavedBlock[block.number] = true;
                blocks.push(block.number);
            }
            s_blockNonce[block.number] += 1;

            s_tradesInBlock[block.number][s_blockNonce[block.number] - 1] = Trade(
                msg.sender,
                uint(params.amountSpecified),
                params.zeroForOne
            );
        }

        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        poolManager.mint(
            address(this),
            input.toId(),
            uint256(-params.amountSpecified)
        );

        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(-params.amountSpecified), 0),
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
                beforeRemoveLiquidity: false, // -- No-op'ing the swap --  //
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

    function checkUpkeep(
        bytes calldata checkdata
    ) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint nextBlockIndex = lastFullfilledBlockIndex + 1;

        // Ensure the block is saved and has trades
        if (!s_isSavedBlock[nextBlockIndex] || s_blockNonce[nextBlockIndex] == 0) {
            return (false, "");
        }

        uint[] memory zeroToOne;
        uint[] memory oneToZero;
        address[] memory zeroToOneAddresses;
        address[] memory oneToZeroAddresses;

        uint tradeCount = s_blockNonce[nextBlockIndex];

        // Initialize temporary arrays with the length of trades
        zeroToOne = new uint[](tradeCount);
        oneToZero = new uint[](tradeCount);
        zeroToOneAddresses = new address[](tradeCount);
        oneToZeroAddresses = new address[](tradeCount);

        uint zeroToOneCount;
        uint oneToZeroCount;

        // Iterate through each trade in the block
        for (uint i = 0; i < tradeCount; i++) {
            Trade memory trade = s_tradesInBlock[nextBlockIndex][i];

            // Append the trade amount and address to the appropriate arrays
            if (trade.isZeroToOne) {
                zeroToOne[zeroToOneCount] = trade.amountSpecified;
                zeroToOneAddresses[zeroToOneCount] = trade.sender;
                zeroToOneCount++;
            } else {
                oneToZero[oneToZeroCount] = trade.amountSpecified;
                oneToZeroAddresses[oneToZeroCount] = trade.sender;
                oneToZeroCount++;
            }
        }

        // Resize the arrays to the actual count of elements
        uint[] memory finalZeroToOne = new uint[](zeroToOneCount);
        uint[] memory finalOneToZero = new uint[](oneToZeroCount);
        address[] memory finalZeroToOneAddresses = new address[](zeroToOneCount);
        address[] memory finalOneToZeroAddresses = new address[](oneToZeroCount);

        for (uint i = 0; i < zeroToOneCount; i++) {
            finalZeroToOne[i] = zeroToOne[i];
            finalZeroToOneAddresses[i] = zeroToOneAddresses[i];
        }
        for (uint i = 0; i < oneToZeroCount; i++) {
            finalOneToZero[i] = oneToZero[i];
            finalOneToZeroAddresses[i] = oneToZeroAddresses[i];
        }

        // Sort the trades
        (finalZeroToOne, finalZeroToOneAddresses) = tradeSort(finalZeroToOne, finalZeroToOneAddresses, 0, int(finalZeroToOne.length - 1));
        (finalOneToZero, finalOneToZeroAddresses) = tradeSort(finalOneToZero, finalOneToZeroAddresses, 0, int(finalOneToZero.length - 1));

        // Encode the result as performData
        performData = abi.encode(finalZeroToOne, finalZeroToOneAddresses, finalOneToZero, finalOneToZeroAddresses);
        upkeepNeeded = (zeroToOneCount > 0 || oneToZeroCount > 0);
    }

    function performUpkeep(bytes calldata performData) external override {

        (
            uint[] memory finalZeroToOne,
            address[] memory finalZeroToOneaddresses,
            uint[] memory finalOneToZero,
            address[] memory finalOneToZeroaddresses
        ) = abi.decode(performData, (uint[], address[], uint[], address[]));
        // define pool key 
        PoolKey memory key = PoolKey({
            currency0: (
                uint160(token0) < uint160(token1)
                    ? Currency.wrap(token0)
                    : Currency.wrap(token1)
            ),
            currency1: (
                uint160(token0) < uint160(token1)
                    ? Currency.wrap(token1)
                    : Currency.wrap(token0)
            ),
            fee: 3000,
            hooks: IHooks(address(this)),
            tickSpacing: 60
        });

        int amountSpecified;

        for (uint i; i<s_blockNonce[block.number]; i++){
            
            // TRY / CATCH swaps
            // Trade[] trades = s_tradesInBlock[lastFullfilledBlockIndex+1];

            // PoolSwapTest(poolSwap).swap(
            //     key,
            //     IPoolManager.SwapParams(
            //         true,
            //         amountSpecified,
            //         79228162514264337593543950336 / 2
            //     ),
            //     PoolSwapTest.TestSettings(false, false),
            //     hex""
            // );
        }

  

    }
}
