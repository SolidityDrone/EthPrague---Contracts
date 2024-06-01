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
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";




contract CounterScript is Script{
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    address constant SEPOLIA_POOLMANAGER = address(0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6);
    address positionManager = 0x39BF2eFF94201cfAA471932655404F63315147a4;
    address poolSwap = 0x841B5A0b3DBc473c8A057E2391014aa4C4751351;
    address token0 = 0x41Afb4518aD277455C1eF6182F35667949cC0b41;
    address token1 = 0xC0c8C84A1f962Af274Ad3E36Dbb81bAD9B3b969C;
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
        
        // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;
        // create key
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
            hooks: IHooks(hook),
            tickSpacing: 60
        });
        // init poolmanager
        int24 tickLower = -600;
        int24 tickUpper = 600;
        uint256 liquidity = 1e18;
        vm.broadcast();
        IPoolManager(SEPOLIA_POOLMANAGER).initialize(key, startingPrice, hex"");
       
         vm.broadcast();
          PoolModifyLiquidityTest(positionManager).modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(liquidity),
                salt: bytes32(0) // idk
            }),
            hex""
        );
        int256 amountSpecified = -6000000;
        // execute a swap
         vm.broadcast();
        PoolSwapTest(poolSwap).swap(
            key,
            IPoolManager.SwapParams(
                true,
                amountSpecified,
                79228162514264337593543950336 / 2
            ),
            PoolSwapTest.TestSettings(false, false),
            hex""
        );
    }
}