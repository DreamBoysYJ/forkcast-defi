// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {HookFactory} from "../src/hook/HookFactory.sol";
import {SwapPriceLoggerHook} from "../src/hook/SwapPriceLoggerHook.sol";
import {HookMiner} from "../src/libs/HookMiner.sol";
import {Hooks} from "../src/libs/Hooks.sol";

contract DeploySwapPriceLoggerHook is Script {
    function run() external {
        // .env : pk, hook_factory, salt
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factoryAddr = vm.envAddress("HOOK_FACTORY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address deployerEOA = vm.addr(deployerPrivateKey);
        console2.log("Deployer EOA:", deployerEOA);
        console2.log("HookFactory:", factoryAddr);
        console2.log("PoolManager:", poolManager);

        // HookMiner로 off-chain에서 salt + 예상 주소 찾기
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager);

        // flags : AFTER_SWAP bit only
        (address expectedHook, bytes32 salt) = HookMiner.find({
            deployer: factoryAddr,
            flags: uint160(Hooks.AFTER_SWAP_FLAG),
            creationCode: creationCode,
            constructorArgs: constructorArgs
        });

        console2.log("HookMiner expected hook:", expectedHook);
        console2.log("HookMiner salt:");
        console2.logBytes32(salt);

        // validate expectedAddr on-chain
        HookFactory factory = HookFactory(factoryAddr);
        address predicted = factory.computeHookAddress(salt);
        console2.log("Factory.computeHookAddress :", predicted);
        if (predicted != expectedHook) {
            console2.log(
                "WARNING : HookMiner expected != factory.computeHookAddress"
            );
        }

        // Deploy Hook through HookFactory
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
