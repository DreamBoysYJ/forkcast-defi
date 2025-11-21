// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Hooks} from "../../src/libs/Hooks.sol";
import {HookMiner} from "../../src/libs/HookMiner.sol";

import {SwapPriceLoggerHook} from "../../src/hook/SwapPriceLoggerHook.sol";

/*
SwapPriceLoggerHook용 유효한 SALT 찾기

forge test --match-test test_swap_price_logger_hook_salt -vvv
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

        // 이 assert가 통과하면, HookMiner가 찾은 salt로 실제 배포한 주소가 동일하다는 뜻
        assertEq(addr, address(new SwapPriceLoggerHook{salt: salt}(pm)));
    }
}
