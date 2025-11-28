// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {HookFactory} from "../src/hook/HookFactory.sol";
import {SwapPriceLoggerHook} from "../src/hook/SwapPriceLoggerHook.sol";
import {HookMiner} from "../src/libs/HookMiner.sol";
import {Hooks} from "../src/libs/Hooks.sol";

/// @title DeploySwapPriceLoggerHook
/// @notice Deploys the SwapPriceLoggerHook via HookFactory using CREATE2 and
///         a pre-mined salt so the hook address encodes AFTER_SWAP flag bits.
/// @dev
/// Usage (high level):
/// 1) Make sure HookFactory is already deployed (see DeployHookFactory.s.sol).
/// 2) Set the following env vars in `.env`:
///    - DEPLOYER_PRIVATE_KEY : EOA that will broadcast the deployment tx
///    - HOOK_FACTORY         : address of the deployed HookFactory
///    - POOL_MANAGER         : Uniswap v4 PoolManager this hook will attach to
/// 3) Run with:
///       forge script script/DeploySwapPriceLoggerHook.s.sol \
///         --rpc-url sepolia --broadcast -vvvv
///
/// The script:
/// - Uses HookMiner to find a salt + expected hook address that satisfies
///   the AFTER_SWAP flag layout.
/// - Verifies the expected address against HookFactory.computeHookAddress.
/// - Deploys the hook via HookFactory and checks the final address.
contract DeploySwapPriceLoggerHook is Script {
    /// @notice Main entrypoint used by `forge script`.
    function run() external {
        // ---------------------------------------------------------------------
        // 1. Load configuration from environment
        // ---------------------------------------------------------------------

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factoryAddr = vm.envAddress("HOOK_FACTORY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address deployerEOA = vm.addr(deployerPrivateKey);
        console2.log("Deployer EOA:", deployerEOA);
        console2.log("HookFactory:", factoryAddr);
        console2.log("PoolManager:", poolManager);

        // ---------------------------------------------------------------------
        // 2. Use HookMiner to search for salt + expected hook address
        // ---------------------------------------------------------------------
        // creationCode of the SwapPriceLoggerHook
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        // constructor(poolManager)

        bytes memory constructorArgs = abi.encode(poolManager);

        // Only AFTER_SWAP flag is set in the hook address
        (address expectedHook, bytes32 salt) = HookMiner.find({
            deployer: factoryAddr,
            flags: uint160(Hooks.AFTER_SWAP_FLAG),
            creationCode: creationCode,
            constructorArgs: constructorArgs
        });

        console2.log("HookMiner expected hook:", expectedHook);
        console2.log("HookMiner salt:");
        console2.logBytes32(salt);

        // ---------------------------------------------------------------------
        // 3. Cross-check with HookFactory.computeHookAddress(salt)
        // ---------------------------------------------------------------------
        HookFactory factory = HookFactory(factoryAddr);
        address predicted = factory.computeHookAddress(salt);
        console2.log("Factory.computeHookAddress :", predicted);
        if (predicted != expectedHook) {
            console2.log(
                "WARNING : HookMiner expected != factory.computeHookAddress"
            );
        }

        // ---------------------------------------------------------------------
        // 4. Deploy the hook via HookFactory using the mined salt
        // ---------------------------------------------------------------------
        vm.startBroadcast(deployerPrivateKey);
        address hook = factory.deploySwapPriceLoggerHook(salt);
        vm.stopBroadcast();
        console2.log("Hook Deployed at : ", hook);
        if (hook == expectedHook) {
            console2.log("OK: deployed hook == expectedHookflags");
        } else {
            console2.log("WRONG : deployed hook != expectedHook");
        }
    }
}
