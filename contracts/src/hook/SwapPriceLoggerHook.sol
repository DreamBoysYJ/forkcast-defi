// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/console2.sol";

import {Hooks} from "../libs/Hooks.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {
    SwapParams,
    ModifyLiquidityParams
} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "../types/uniswapV4/BeforeSwapDelta.sol";

contract SwapPriceLoggerHook {
    using PoolIdLibrary for PoolKey;

    error NotPoolManager();
    error HookNotImplemented();

    IPoolManager public immutable poolManager;

    event SwapPriceLogged(
        PoolId indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint256 timestamp
    );

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
        //Hooks.validateHookPermissions(address(this), getHookPermissions());
    }

    function getHookPermissions()
        public
        pure
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true, // ✅ 여기만 true
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) external onlyPoolManager returns (bytes4) {
        // 안 쓸 거면 그냥 selector만 돌려주면 됨
        return this.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24
    ) external onlyPoolManager returns (bytes4) {
        return this.afterInitialize.selector;
    }

    // ----------------- Add Liquidity -----------------

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        // 카운팅 하고 싶으면 여기서 ++ 가능
        return this.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        // 아무 영향 없게 ZERO delta 리턴
        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ----------------- Remove Liquidity -----------------

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        return this.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ----------------- Swap -----------------

    function beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        // 가격/슬리피지 가드 넣고 싶으면 여기서 가능
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address, // sender
        PoolKey calldata key,
        SwapParams calldata, // params
        BalanceDelta, // delta
        bytes calldata // hookData
    ) external onlyPoolManager returns (bytes4, int128) {
        // ✅ 여기서 가격/틱 읽어서 이벤트 로그
        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96, int24 tick, , ) = StateLibrary.getSlot0(
            poolManager,
            poolId
        );

        emit SwapPriceLogged(poolId, tick, sqrtPriceX96, block.timestamp);

        return (this.afterSwap.selector, 0);
    }

    // ----------------- Donate -----------------

    function beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        return this.beforeDonate.selector;
    }

    function afterDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        return this.afterDonate.selector;
    }
}
