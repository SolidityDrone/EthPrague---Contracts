// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/CaptainHappyHook.sol";

contract CaptainHappyHookTest is Test {
    CaptainHappyHook public happy;

    function test_swap() public {
        happy = new CaptainHappyHook();
        happy.beforeSwap( , , ,);
    }
}

// beforeSwap(
//         address,
//         PoolKey calldata,
//         IPoolManager.SwapParams calldata params,
//         bytes calldata
