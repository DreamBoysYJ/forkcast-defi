// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// 네 프로젝트 경로에 맞게 수정
import {StrategyRouter} from "../src/router/StrategyRouter.sol";

contract InitStrategyRouterPermit2 is Script {
    function run() external {
        // 1) env 로드
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address routerAddr = vm.envAddress("STRATEGY_ROUTER");
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");

        // 유저들이 사용할 풀의 두 토큰
        address token0 = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        address token1 = vm.envAddress("LINK_UNDERLYING_SEPOLIA");

        console2.log("Deployer (admin):", deployer);
        console2.log("StrategyRouter  :", routerAddr);
        console2.log("PoolManager     :", poolManagerAddr);
        console2.log("token0          :", token0);
        console2.log("token1          :", token1);

        StrategyRouter router = StrategyRouter(routerAddr);

        // 2) admin 권한으로 initPermit2 호출
        vm.startBroadcast(deployerPrivateKey);

        router.initPermit2(token0, token1, poolManagerAddr);

        vm.stopBroadcast();

        console2.log("initPermit2 called successfully");
    }
}
