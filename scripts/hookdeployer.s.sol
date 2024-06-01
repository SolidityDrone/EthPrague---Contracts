// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "../src/MockERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {NoOpSwap} from "../src/NoOpSwap.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

contract CounterScript is Script{
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    address constant SEPOLIA_POOLMANAGER = address(0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6);
    address positionManager = 0x39BF2eFF94201cfAA471932655404F63315147a4;
    address poolSwap = 0x841B5A0b3DBc473c8A057E2391014aa4C4751351;
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(NoOpSwap).creationCode, abi.encode(address(SEPOLIA_POOLMANAGER)));

        // Deploy the hook using CREATE2
        vm.broadcast();
        NoOpSwap hook = new NoOpSwap{salt: salt}(IPoolManager(address(SEPOLIA_POOLMANAGER)));
        console.logAddress(address(hook));
        
        // vm.broadcast();
        // address token0 = address(new MockERC20("Token0", "T0"));
        // console.logAddress(address(token0));
        
        // vm.broadcast();
        // address token1 = address(new MockERC20("Token1", "T1"));
        // console.logAddress(address(token1));
        // vm.broadcast();
        // IERC20(token0).approve(positionManager, type(uint).max);
        // vm.broadcast();
        // IERC20(token1).approve(positionManager, type(uint).max);

        // vm.broadcast();
        // IERC20(token0).approve(poolSwap, type(uint).max);
        // vm.broadcast();
        // IERC20(token1).approve(poolSwap, type(uint).max);
    }
}