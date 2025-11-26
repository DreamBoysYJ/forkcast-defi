// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {HookFactory} from "../src/hook/HookFactory.sol";

contract DeployHookFactroy is Script {
    function run() external {
        // Pk, PoolManager Addr
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");

        // owner
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy HookFactory
        HookFactory factory = new HookFactory(poolManager, owner);
        console2.log("HookFactory deployed at : ", address(factory));
        console2.log("owner:", owner);
        console2.log("poolManager:", poolManager);
    }
}
