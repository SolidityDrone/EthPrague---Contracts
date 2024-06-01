// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/NoOpSwap.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {HookMiner} from "./utils/HookMiner.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NoOpSwapTest is Test {
    address sepoliaPoolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    address create2Proxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address positionManager = 0x39BF2eFF94201cfAA471932655404F63315147a4;
    address poolSwap = 0x841B5A0b3DBc473c8A057E2391014aa4C4751351;
    address hookdeployer = 0xFdF701d3768c88a338699f2E69eCF6c7dDd00D5e;
    address token0;
    address token1;
    NoOpSwap hook;

    constructor() {}

    function setUp() public {
        token0 = address(new MockERC20("Token0", "T0"));
        token1 = address(new MockERC20("Token1", "T1"));
        IERC20(token0).approve(positionManager, type(uint).max);
        IERC20(token1).approve(positionManager, type(uint).max);

        IERC20(token0).approve(poolSwap, type(uint).max);
        IERC20(token1).approve(poolSwap, type(uint).max);
    }

    function test_poolInit() public {
        // set flags
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG
        );
        // find salt and address
        vm.prank(create2Proxy);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(create2Proxy),
            flags,
            type(NoOpSwap).creationCode,
            abi.encode(sepoliaPoolManager)
        );
        hook = new NoOpSwap{salt: salt}(
            IPoolManager(address(sepoliaPoolManager))
        );
        console.logAddress(hookAddress);
        require(
            address(hook) == hookAddress,
            "SponsoredTest: hook address mismatch"
        );

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
        IPoolManager(sepoliaPoolManager).initialize(key, startingPrice, hex"");

        int24 tickLower = -600;
        int24 tickUpper = 600;
        uint256 liquidity = 1e18;
        // add liquidity
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

        // // try catch one that is too big
        // try
        // PoolSwapTest(poolSwap).swap(
        // key,
        // IPoolManager.SwapParams(true, amountSpecified, type(uint160).max), // this will fail.
        // PoolSwapTest.TestSettings(false, false),
        // hex'')

        // {

        // }catch (bytes memory reason){

        // }
    }
}
