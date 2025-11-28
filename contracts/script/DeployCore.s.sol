// script/DeployCore.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {Miniv4SwapRouter} from "../src/uniswapV4/Miniv4SwapRouter.sol";
import {AccountFactory} from "../src/factory/AccountFactory.sol";
import {UserAccount} from "../src/accounts/UserAccount.sol";
import {StrategyRouter} from "../src/router/StrategyRouter.sol";
import {StrategyLens} from "../src/lens/StrategyLens.sol";

/// @title DeployCore
/// @notice Foundry script that deploys the core contracts required for the
///         Forkcast one-shot Aave + Uniswap v4 strategy:
///         - Mini v4 swap router
///         - AccountFactory (vault factory)
///         - StrategyRouter (Aave + Uniswap orchestrator)
///         - StrategyLens (read-only dashboard / view layer)
/// @dev
/// - This script only deploys contracts; it does NOT:
///     - initialize the v4 pool (see InitAaveLinkHookedPool.s.sol)
///     - wire router pool config / Permit2 (see InitStrategyRouter*.s.sol)
/// - All external addresses (Aave & Uniswap infra, Permit2) are taken from
///   environment variables so the same script can be reused across networks.
contract DeployCore is Script {
    /// @dev Private key used as the deployer for all contracts.
    ///      It is expected to be funded on the network in advance.
    uint256 internal deployerPk;

    /// @notice Load the deployer pk from .env.
    /// @dev    "DEPLOYER_PRIVATE_KEY" must be set in  .env
    function setUp() public {
        deployerPk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    /// @notice Deploy all core contracts in a single broadcasted transaction
    ///         sequence.
    /// @dev
    /// Execution order:
    /// 1. Read external dependency addresses (Aave, Uniswap, Permit2).
    /// 2. Deploy Mini v4 swap router (needs PoolManager).
    /// 3. Deploy AccountFactory (needs Aave PoolAddressesProvider).
    /// 4. Deploy StrategyRouter (wires Aave, factory, swap router, POSM, Permit2).
    /// 5. Deploy StrategyLens (read-only views over Aave + v4 + router).
    function run() external {
        vm.startBroadcast(deployerPk);

        address deployerAddr = vm.addr(deployerPk);

        // ---------------------------------------------------------------------
        // 1. External protocol addresses (read from env)
        // ---------------------------------------------------------------------
        // Aave v3
        address aaveAddressesProvider = vm.envAddress(
            "AAVE_POOL_ADDRESSES_PROVIDER"
        );
        address aavePool = vm.envAddress("AAVE_POOL");
        address aaveDataProvider = vm.envAddress("AAVE_PROTOCOL_DATA_PROVIDER");
        address aaveOracle = vm.envAddress("AAVE_ORACLE");

        // Uniswap v4 + Permit2
        address uniPoolManager = vm.envAddress("POOL_MANAGER");
        address uniPositionManager = vm.envAddress("POSITION_MANAGER");
        address permit2 = vm.envAddress("PERMIT2");

        // ---------------------------------------------------------------------
        // 2. Deploy Mini v4 swap router
        //
        // Thin wrapper around Uniswap v4 PoolManager that:
        // - performs exact-input swaps for the demo strategy
        // - is also used by the demo trader backend to generate fees
        // ---------------------------------------------------------------------
        Miniv4SwapRouter miniRouter = new Miniv4SwapRouter(uniPoolManager);
        console2.log("MiniSwapRouter :", address(miniRouter));

        // ---------------------------------------------------------------------
        // 3. Deploy AccountFactory
        //
        // Factory that lazily creates per-user vaults (UserAccount) that:
        // - hold Aave aTokens / debt
        // - are operated by StrategyRouter as `operator`
        // ---------------------------------------------------------------------
        AccountFactory factory = new AccountFactory(aaveAddressesProvider);
        console2.log("AccountFactory:", address(factory));

        // ---------------------------------------------------------------------
        // 4. Deploy StrategyRouter
        //
        // Main orchestrator that executes the one-shot strategy:
        //   supply (Aave) → borrow → swap / LP on Uniswap v4.

        // ---------------------------------------------------------------------

        StrategyRouter router = new StrategyRouter(
            aaveAddressesProvider,
            address(factory),
            aaveDataProvider,
            address(miniRouter),
            uniPositionManager,
            permit2
        );

        console2.log("StrategyRouter :", address(router));

        // ---------------------------------------------------------------------
        // 5. Deploy StrategyLens
        //
        // Read-only helper that aggregates:
        // - Aave account data (collateral, debt, HF…)
        // - Uniswap v4 LP positions
        // - StrategyRouter vault / position information
        //
        // ---------------------------------------------------------------------
        StrategyLens lens = new StrategyLens(
            deployerAddr,
            aaveAddressesProvider,
            aavePool,
            aaveDataProvider,
            address(factory),
            aaveOracle,
            uniPoolManager,
            uniPositionManager,
            address(router)
        );
        console2.log("StrategyLens:", address(lens));

        vm.stopBroadcast();
    }
}
