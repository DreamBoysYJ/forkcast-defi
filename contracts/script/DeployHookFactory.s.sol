// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {HookFactory} from "../src/hook/HookFactory.sol";

/// @title DeployHookFactory
/// @notice Foundry script that deploys the Uniswap v4 HookFactory used by the
///         Forkcast demo.
/// @dev
/// - This script only deploys the factory contract itself.
/// - Actual hook instances (e.g. SwapPriceLoggerHook) are deployed via
///   separate scripts that call into this factory.
/// - All external addresses are taken from environment variables so the same
///   script can be reused across networks.
contract DeployHookFactroy is Script {
    /// @notice Main entrypoint used by `forge script`.
    /// @dev
    /// Reads:
    /// - DEPLOYER_PRIVATE_KEY : EOA that will deploy and own the factory
    /// - POOL_MANAGER         : Uniswap v4 PoolManager address
    function run() external {
        // ---------------------------------------------------------------------
        // 1. Load config from environment
        // ---------------------------------------------------------------------
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");

        // Deployer / owner EOA
        address owner = vm.addr(deployerPrivateKey);

        // ---------------------------------------------------------------------
        // 2. Broadcast deployment txs from the deployer EOA
        // ---------------------------------------------------------------------
        vm.startBroadcast(deployerPrivateKey);

        // Deploy HookFactory
        // - `poolManager` is the v4 PoolManager this factory will target
        // - `owner` is allowed to manage / configure hooks created by factory
        HookFactory factory = new HookFactory(poolManager, owner);
        console2.log("HookFactory deployed at : ", address(factory));
        console2.log("owner:", owner);
        console2.log("poolManager:", poolManager);
    }
}
