// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {StrategyRouter} from "../src/router/StrategyRouter.sol";

/// @title InitStrategyRouterPermit2
/// @notice One–time initializer script for StrategyRouter’s Permit2 / pool config.
/// @dev
/// Responsibilities:
/// - Reads the deployed StrategyRouter + Uniswap v4 PoolManager + token addresses
///   from .env.
/// - Calls `StrategyRouter.initPermit2(token0, token1, poolManager)` as the admin
///   (the deployer EOA).
///
/// Env requirements:
/// - DEPLOYER_PRIVATE_KEY        : admin EOA for StrategyRouter
/// - STRATEGY_ROUTER             : deployed StrategyRouter address
/// - POOL_MANAGER                : Uniswap v4 PoolManager address
/// - AAVE_UNDERLYING_SEPOLIA     : token0 in the AAVE/LINK pool
/// - LINK_UNDERLYING_SEPOLIA     : token1 in the AAVE/LINK pool
///
/// Typical usage:
/// - Run once right after deploying StrategyRouter and the v4 pool:
///     forge script script/InitStrategyRouterPermit2.s.sol \
///       --rpc-url sepolia \
///       --broadcast
/// - After this, the router knows which two tokens / poolManager it is allowed
///   to work with via Permit2.

contract InitStrategyRouterPermit2 is Script {
    function run() external {
        // ---------------------------------------------------------------------
        // 1. Load env + resolve addresses
        // ---------------------------------------------------------------------

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address routerAddr = vm.envAddress("STRATEGY_ROUTER");
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");

        //
        address token0 = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        address token1 = vm.envAddress("LINK_UNDERLYING_SEPOLIA");

        console2.log("Deployer (admin):", deployer);
        console2.log("StrategyRouter  :", routerAddr);
        console2.log("PoolManager     :", poolManagerAddr);
        console2.log("token0          :", token0);
        console2.log("token1          :", token1);

        StrategyRouter router = StrategyRouter(routerAddr);

        // ---------------------------------------------------------------------
        // 2. Call initPermit2 as the router admin
        // ---------------------------------------------------------------------
        vm.startBroadcast(deployerPrivateKey);

        router.initPermit2(token0, token1, poolManagerAddr);

        vm.stopBroadcast();

        console2.log("initPermit2 called successfully");
    }
}
