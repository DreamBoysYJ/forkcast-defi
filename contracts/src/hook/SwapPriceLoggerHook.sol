// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

/// @title SwapPriceLoggerHook
/// @notice Uniswap v4 hook that is read-only for accounting and only logs price/tick on swaps.
contract SwapPriceLoggerHook {
    using PoolIdLibrary for PoolKey;

    error NotPoolManager();
    error HookNotImplemented();

    /// @notice The PoolManager this hook is wired to. No other caller is accepted.
    IPoolManager public immutable poolManager;

    /// @notice Emitted on every swap, capturing the pool id, tick and sqrtPriceX96 at that moment.
    event SwapPriceLogged(
        PoolId indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint256 timestamp
    );

    /// @dev Simple guard: hooks must only ever be called by the bound PoolManager.
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @param _poolManager The v4 PoolManager this hook instance is attached to.
    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);

        // If you want safety checks on permissions at deploy time, uncomment:
        //Hooks.validateHookPermissions(address(this), getHookPermissions());
    }

    /// @notice Declare which hook callbacks are actually implemented by this contract.
    /// @dev Only `afterSwap` is enabled; all others are effectively no-ops.
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
                afterSwap: true, // ✅ true
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // ----------------- Initialize -----------------

    /// @dev Unused, but must return its selector to satisfy the hook interface.
    function beforeInitialize(
        address,
        PoolKey calldata,
        uint160
    ) external onlyPoolManager returns (bytes4) {
        return this.beforeInitialize.selector;
    }

    /// @dev Unused, but kept for completeness with the v4 hook surface.
    function afterInitialize(
        address,
        PoolKey calldata,
        uint160,
        int24
    ) external onlyPoolManager returns (bytes4) {
        return this.afterInitialize.selector;
    }

    // ----------------- Add Liquidity -----------------

    /// @dev Place to plug in liquidity-related accounting or limits if needed later.
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        return this.beforeAddLiquidity.selector;
    }

    /// @dev Returns a zero delta so this hook never mutates pool accounting.
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ----------------- Remove Liquidity -----------------

    /// @dev Symmetric to `beforeAddLiquidity`, reserved for future extensions.
    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        return this.beforeRemoveLiquidity.selector;
    }

    /// @dev Returns a zero delta so removing liquidity is untouched by this hook.
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

    /// @dev Hook point to introduce price / slippage guards in the future.
    function beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Core logic: read current price/tick from pool state and emit a structured event.
    /// @dev Does not touch balances or fees; the second return value is zero to keep swaps unchanged.
    function afterSwap(
        address, // sender
        PoolKey calldata key,
        SwapParams calldata, // params
        BalanceDelta, // delta
        bytes calldata // hookData
    ) external onlyPoolManager returns (bytes4, int128) {
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
