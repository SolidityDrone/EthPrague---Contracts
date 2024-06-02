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
import {AutomationCompatibleInterface} from "lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract NoOpSwap is BaseHook, AutomationCompatibleInterface {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    uint internal lastFullfilledBlockIndex;
    address internal forwarder;
    uint[] blocks;
    mapping(uint=>Trade[200]) internal s_tradesInBlock;
    mapping(uint=>uint) internal s_blockNonce;
    mapping(uint=>bool) internal s_isSavedBlock;
    

    struct Trade{
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
        address[] memory addrArr
    ) internal pure returns (uint[] memory, address[] memory) {
        int i = 0;
        int j = arr.length;
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
            if (msg.sender == forwarder){
               return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
            }   

            if (msg.sender != forwarder){
                if (s_isSavedBlock[block.number] == false){
                    s_isSavedBlock[block.number] = true;    
                    blocks.push(block.number);   
                } 
                 s_blockNonce[block.number] +=1;

                if (!params.zeroForOne){
                    s_tradesInBlock[block.number][s_blockNonce[block.number]] = Trade(msg.sender, params.amountSpecified, false);
                } 
                if (params.zeroForOne){
                    s_tradesInBlock[block.number][s_blockNonce[block.number]] = Trade(msg.sender, params.amountSpecified, true);
                }
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
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
       // list of trades atob and btoa
       Trades[] trades = s_tradesInBlock[lastFullfilledBlockIndex + 1];
       Trades[] tradesAtoB;
       Trades[] tradesBtoA;

       for (uint256 i = 0; i < trades.length; i++) {
            if (trades[i].isZeroToOne) {
                // tradesAtoB.push(trades[i]);
            }
            else {
                // tradesBtoA.push(trades[i]);
            }       
        }
    }

    function tradeSortNew(Trades[] memory trades) internal pure returns (uint[] memory, address[] memory) {
        int i = left = 0;
        int j = right = arr.length;

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
 

        struct Trade{
        address sender;
        uint amountSpecified;
        bool isZeroToOne;
    }

    function performUpkeep(bytes calldata performData) external override {
       
    }
}
