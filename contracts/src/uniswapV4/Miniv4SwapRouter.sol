// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TStore} from "../utils/TStore.sol";
import {SafeCast} from "../libs/SafeCast.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "../interfaces/uniswapV4/IUnlockCallback.sol";
import {
    BalanceDelta,
    BalanceDeltaLibrary
} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/// @title Miniv4SwapRouter
/// @notice Minimal, single-purpose router for Uniswap v4 that supports:
///         - exact-in single-pool swaps
///         - symmetric “unlock” flow via PoolManager
///         - ETH and ERC20 input / output
///
/// @dev Design goals:
///      - keep the public surface area as small as possible
///      - push all stateful accounting into PoolManager
///      - make the swap path easy to reason about / audit:
///           user → router → PoolManager.swap() → router.unlockCallback()
///           → poolManager.take/sync/settle → router.refund()
contract Miniv4SwapRouter is TStore, IUnlockCallback {
    // Library
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for int128;
    using SafeCast for uint128;

    /// @notice Global price guardrails for Uniswap v4 swaps.
    /// @dev We use “almost min/max” when setting sqrtPriceLimit in swaps,
    ///      to avoid hitting exact boundaries while still allowing full-range execution.
    uint160 constant MIN_SQRT_PRICE = 4295128739;
    uint160 constant MAX_SQRT_PRICE =
        1461446703485210103287273052203988822378723970342;

    /// @dev Simple action discriminator stored via TStore.
    ///      Useful if we ever extend this router with more verbs.
    uint256 private constant SWAP_EXACT_IN_SINGLE = 0x06;

    /// @notice Canonical Uniswap v4 PoolManager this router talks to.
    /// @dev Immutable: each router instance is bound to a single manager
    IPoolManager public immutable poolManager;

    /// @notice Parameters for a single-pool exact input swap.
    /// @dev    This struct is carried end-to-end through unlock():
    ///         - into PoolManager via `unlock`
    ///         - back into `unlockCallback` for actual swap execution.
    struct ExactInputSingleParams {
        PoolKey poolKey;
        /// @dev Swap direction:
        ///        - true  : token0 → token1  (price decreasing)
        ///        - false : token1 → token0  (price increasing)
        bool zeroForOne;
        /// @dev Exact amount of input tokens.
        uint128 amountIn;
        /// @dev Minimum acceptable amount of output tokens (slippage bound).
        uint128 amountOutMin;
        /// @dev Arbitrary data forwarded to pool hooks, if any.
        bytes hookData;
    }

    error UnsupportedAction(uint256 action);

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "not pool manager");
        _;
    }

    /// @param _poolManager Canonical Uniswap v4 PoolManager address for this router.
    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @dev Allow receiving ETH for native-currency swaps/settles.
    receive() external payable {}

    /// @notice Entry point called by PoolManager during `unlock`.
    /// @dev    Control flow:
    ///          1. PoolManager calls `unlockCallback` with opaque `data`.
    ///          2. We inspect the current `action` stored by TStore.
    ///          3. For supported actions, decode params and perform the swap.
    ///          4. Take / settle balances in PoolManager and return packed result.
    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        uint256 action = _getAction();

        if (action == SWAP_EXACT_IN_SINGLE) {
            (address msgSender, ExactInputSingleParams memory params) = abi
                .decode(data, (address, ExactInputSingleParams));

            (int128 amount0, int128 amount1) = _swap(
                params.poolKey,
                params.zeroForOne,
                -int256(uint256(params.amountIn)),
                params.hookData
            );

            (
                address currencyIn,
                address currencyOut,
                uint256 amountIn,
                uint256 amountOut
            ) = params.zeroForOne
                    ? (
                        Currency.unwrap(params.poolKey.currency0),
                        Currency.unwrap(params.poolKey.currency1),
                        (-amount0).toUint256(),
                        amount1.toUint256()
                    )
                    : (
                        Currency.unwrap(params.poolKey.currency1),
                        Currency.unwrap(params.poolKey.currency0),
                        (-amount1).toUint256(),
                        amount0.toUint256()
                    );

            require(amountOut >= params.amountOutMin, "amount out < min");

            _takeAndSettle({
                dst: msgSender,
                currencyIn: currencyIn,
                currencyOut: currencyOut,
                amountIn: amountIn,
                amountOut: amountOut
            });
            return abi.encode(amountOut);
        } else {
            revert UnsupportedAction(action);
        }
    }

    /// @notice Public entrypoint for a single-pool “exact in” swap.
    /// @dev    High-level flow:
    ///          1. Pull `amountIn` from the caller into the router.
    ///          2. Call `poolManager.unlock` with encoded params.
    ///             → this triggers `unlockCallback`, which executes `_swap`
    ///               + `_takeAndSettle`.
    ///          3. Decode the resulting amountOut.
    ///          4. Refund any leftover input (overpaid ETH or unused ERC20) back
    ///             to the caller.
    function swapExactInputSingle(
        ExactInputSingleParams calldata params
    )
        external
        payable
        setAction(SWAP_EXACT_IN_SINGLE)
        returns (uint256 amountOut)
    {
        // Resolve which side is the input token for this swap direction.
        address currencyIn = params.zeroForOne
            ? Currency.unwrap(params.poolKey.currency0)
            : Currency.unwrap(params.poolKey.currency1);

        // Pull tokens (or ETH) into the router.
        _transferIn(currencyIn, msg.sender, params.amountIn);

        // Execute the swap via PoolManager's optimistic `unlock` mechanism.
        bytes memory res = poolManager.unlock(abi.encode(msg.sender, params));
        amountOut = abi.decode(res, (uint256));

        // Clean up any dust: return unused ETH or ERC20 back to the user.
        _refund(currencyIn, msg.sender);
    }

    /// @dev Returns any leftover ETH/ERC20 to the caller after the swap.
    /// @notice Best-effort dust cleanup; swap correctness does not depend on this.
    function _refund(address token, address to) private returns (uint256) {
        uint256 bal = (token == address(0))
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            if (token == address(0)) {
                (bool ok, ) = to.call{value: bal}("");
                require(ok, "refund ETH failed");
            } else {
                require(IERC20(token).transfer(to, bal), "refund ERC20 failed");
            }
        }
        return bal;
    }

    /// @dev Thin wrapper around PoolManager.swap that:
    ///        - enforces sane price limits
    ///        - preserves “amountSpecified < 0 = exact in” convention
    ///      Returns raw BalanceDelta so the caller can decide how to interpret it.
    function _swap(
        PoolKey memory key,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) private returns (int128 amount0, int128 amount1) {
        BalanceDelta delta = poolManager.swap({
            key: key,
            params: IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                // amountSpecified < 0 = amount in
                // amountSpecified > 0 = amount out
                amountSpecified: amountSpecified,
                // price = Currency 1 / currency 0
                // 0 for 1 = price decreases
                // 1 for 0 = price increases
                sqrtPriceLimitX96: zeroForOne
                    ? MIN_SQRT_PRICE + 1
                    : MAX_SQRT_PRICE - 1
            }),
            hookData: hookData
        });
        return (delta.amount0(), delta.amount1());
    }

    /// @dev Handles the “post-swap” accounting with PoolManager:
    ///        - pulls `currencyOut` from PoolManager to `dst`
    ///        - syncs the input currency delta
    ///        - settles the input by either:
    ///            * forwarding ETH, or
    ///            * transferring ERC20 and calling settle().
    function _takeAndSettle(
        address dst,
        address currencyIn,
        address currencyOut,
        uint256 amountIn,
        uint256 amountOut
    ) private {
        poolManager.take({
            currency: Currency.wrap(currencyOut),
            to: dst,
            amount: amountOut
        });
        poolManager.sync(Currency.wrap(currencyIn));

        if (currencyIn == address(0)) {
            poolManager.settle{value: amountIn}();
        } else {
            IERC20(currencyIn).transfer(address(poolManager), amountIn);
            poolManager.settle();
        }
    }

    /// @dev Unified entry for ingesting ETH or ERC20 from a source address.
    ///      - ETH  : validate msg.value and trust the CallContext
    ///      - ERC20: rely on transferFrom and standard allowance.
    function _transferIn(address token, address from, uint256 amount) private {
        if (token == address(0)) {
            require(msg.value == amount, "msg.value != amount");
        } else {
            require(
                IERC20(token).transferFrom(from, address(this), amount),
                "transferFrom failed"
            );
        }
    }
}
