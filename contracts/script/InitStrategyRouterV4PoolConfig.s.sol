// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {StrategyRouter} from "../src/router/StrategyRouter.sol";

/// @title InitStrategyRouterV4PoolConfig
/// @notice One–time script to set Uniswap v4 pool configuration on StrategyRouter.
/// @dev
/// This script:
/// - Rebuilds the AAVE/LINK + Hook PoolKey (must match the pool used on-chain).
/// - Derives the full-range tick band based on v4’s MIN_TICK / MAX_TICK.
/// - Calls `StrategyRouter.setUniswapV4PoolConfig(key, lower, upper)` as the admin.
///
/// Env requirements:
/// - DEPLOYER_PRIVATE_KEY        : admin EOA for StrategyRouter
/// - STRATEGY_ROUTER             : deployed StrategyRouter address
/// - AAVE_UNDERLYING_SEPOLIA     : AAVE ERC20 address on Sepolia
/// - LINK_UNDERLYING_SEPOLIA     : LINK ERC20 address on Sepolia
/// - HOOK                        : deployed SwapPriceLoggerHook (or compatible) address
///
/// Why separate from deployment?
/// - Core contracts can be deployed once (router, lens, factory, etc.).
/// - v4 pool configuration (tokens, hook, tick range) may be iterated on
///   or re-initialized without redeploying the entire router.
///
/// Typical usage:
/// - After the v4 pool + hook are deployed and liquidity is bootstrapped:
///     forge script script/InitStrategyRouterV4PoolConfig.s.sol \
///       --rpc-url sepolia \
///       --broadcast

contract InitStrategyRouterV4PoolConfig is Script {
    using PoolIdLibrary for PoolKey;

    // Tokens + hook for the AAVE/LINK pool
    address public AAVE;
    address public LINK;
    IHooks public hook;

    /// @dev Build the canonical PoolKey for the AAVE/LINK hooked pool.
    /// @notice
    /// - Sorts AAVE/LINK by address to determine currency0/currency1.
    /// - Uses fee = 3000 (0.3%) and tickSpacing = 10.
    /// - Attaches the SwapPriceLoggerHook (or compatible) as the hooks contract.

    function _buildAaveLinkPoolKey()
        internal
        view
        returns (PoolKey memory key)
    {
        address token0;
        address token1;

        if (AAVE < LINK) {
            token0 = AAVE;
            token1 = LINK;
        } else {
            token0 = LINK;
            token1 = AAVE;
        }

        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 10,
            hooks: hook
        });
    }

    /// @notice Script entrypoint: wires the v4 pool config into StrategyRouter.
    function run() external {
        // ---------------------------------------------------------------------
        // 1. Load env + resolve addresses
        // ---------------------------------------------------------------------
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        address routerAddr = vm.envAddress("STRATEGY_ROUTER");
        AAVE = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        LINK = vm.envAddress("LINK_UNDERLYING_SEPOLIA");
        address hookAddr = vm.envAddress("HOOK");

        hook = IHooks(hookAddr);

        console2.log("Deployer       :", vm.addr(pk));
        console2.log("StrategyRouter :", routerAddr);
        console2.log("AAVE           :", AAVE);
        console2.log("LINK           :", LINK);
        console2.log("Hook           :", hookAddr);

        // ---------------------------------------------------------------------
        // 2. Build PoolKey + derive full-range ticks
        // ---------------------------------------------------------------------
        PoolKey memory key = _buildAaveLinkPoolKey();

        // Full-range ticks based on v4 TickMath + pool tickSpacing
        int24 tickSpacing = key.tickSpacing; // = 10
        int24 lower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 upper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        StrategyRouter router = StrategyRouter(routerAddr);

        // ---------------------------------------------------------------------
        // 3. Configure StrategyRouter with the v4 pool settings
        // ---------------------------------------------------------------------
        vm.startBroadcast(pk);

        // Tell the router which v4 pool (PoolKey + tick range) it should use
        // when entering LP positions. This is typically an admin-only,
        // rarely-changed operation.
        router.setUniswapV4PoolConfig(key, lower, upper);
        vm.stopBroadcast();

        PoolId poolId = key.toId();
        // ---------------------------------------------------------------------
        // 4. Log final pool config for verification
        // ---------------------------------------------------------------------
        console2.log("Set pool config:");
        console2.log("  poolId      :");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("  currency0   :", Currency.unwrap(key.currency0));
        console2.log("  currency1   :", Currency.unwrap(key.currency1));
        console2.log("  fee         :", key.fee);
        console2.log("  tickSpacing :", key.tickSpacing);
        console2.log("  hooks       :", address(key.hooks));
        // console2.log("  lower/upper :", lower, upper);
    }
}
