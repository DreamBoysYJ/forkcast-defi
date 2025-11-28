// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Hooks} from "../../src/libs/Hooks.sol";
import {HookMiner} from "../../src/libs/HookMiner.sol";

import {SwapPriceLoggerHook} from "../../src/hook/SwapPriceLoggerHook.sol";

/**
 * @notice Utility test to pre-compute a valid CREATE2 salt for SwapPriceLoggerHook.
 *
 * How to use:
 *  - Runs HookMiner.find with AFTER_SWAP flag and the hook’s creation code.
 *  - Prints the deployer, derived hook address, and salt to the console.
 *  - Asserts that deploying with that salt actually produces the same address.
 *
 * This is a one-off helper: run it when you need a deterministic hook address
 * for v4 pool initialization.
 *
 * forge test --match-test test_swap_price_logger_hook_salt -vvv
 */

contract FindSwapPriceLoggerHookSalt is Test {
    function find(
        address deployer,
        bytes memory code,
        bytes memory args,
        uint160 flags
    ) private returns (address, bytes32) {
        (address addr, bytes32 salt) = HookMiner.find({
            deployer: deployer,
            flags: flags,
            creationCode: code,
            constructorArgs: args
        });

        console.log("Deployer:", deployer);
        console.log("Hook address:", addr);
        console.log("Hook salt:");
        console.logBytes32(salt);

        return (addr, salt);
    }

    function test_swap_price_logger_hook_salt() public {
        address pm = vm.envAddress("POOL_MANAGER");

        (address addr, bytes32 salt) = find(
            address(this),
            type(SwapPriceLoggerHook).creationCode,
            abi.encode(pm),
            uint160(Hooks.AFTER_SWAP_FLAG)
        );

        // Sanity check: deploying with the mined salt must yield the same hook address.
        assertEq(addr, address(new SwapPriceLoggerHook{salt: salt}(pm)));
    }
}
