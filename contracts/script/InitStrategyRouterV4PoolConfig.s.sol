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

contract InitStrategyRouterV4PoolConfig is Script {
    using PoolIdLibrary for PoolKey;

    address public AAVE;
    address public LINK;
    IHooks public hook;

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

    function run() external {
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

        PoolKey memory key = _buildAaveLinkPoolKey();

        // 풀레인지 기본값
        int24 tickSpacing = key.tickSpacing; // = 10
        int24 lower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 upper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        StrategyRouter router = StrategyRouter(routerAddr);

        vm.startBroadcast(pk);
        router.setUniswapV4PoolConfig(key, lower, upper);
        vm.stopBroadcast();

        PoolId poolId = key.toId();
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
