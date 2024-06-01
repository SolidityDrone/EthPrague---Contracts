// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/NoOpSwap.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {HookMiner} from "./utils/HookMiner.sol";
contract NoOpSwapTest is Test{
    address sepoliaPoolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    address create2Proxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address token0;
    address token1;
    NoOpSwap hook;
    constructor(){}
    
    function setUp() public {
       token0 = address(new MockERC20("Token0", "T0"));
       token1 = address(new MockERC20("Token1", "T1"));
    }
    
    function test_poolInit() public {

        uint160 flags = uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_SWAP_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(NoOpSwap).creationCode,
            abi.encode(sepoliaPoolManager)
        );
        hook = new NoOpSwap{salt: salt}(IPoolManager(address(sepoliaPoolManager)));
        require(
            address(hook) == hookAddress,
            "SponsoredTest: hook address mismatch"
        );
        
       // floor(sqrt(1) * 2^96)
        uint160 startingPrice = 79228162514264337593543950336;

        PoolKey memory uninitializedKey = PoolKey({
           currency0: Currency.wrap(token0),
           currency1: Currency.wrap(token1),
           fee: 3000,
           hooks: IHooks(hook),
           tickSpacing: 60
        });
        

        IPoolManager(sepoliaPoolManager).initialize(uninitializedKey, startingPrice, hex'');
    }
     
    
    

}
