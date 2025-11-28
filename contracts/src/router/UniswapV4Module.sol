// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {Miniv4SwapRouter} from "../../src/uniswapV4/Miniv4SwapRouter.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {
    IERC721
} from "v4-core/lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {
    IPositionManager
} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {
    IERC20
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {
    LiquidityAmounts
} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {
    IERC20
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    PositionInfo,
    PositionInfoLibrary
} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {UniswapV4LiquidityPreview} from "../libs/UniswapV4LiquidityPreview.sol";

// @title UniswapV4Module
/// @notice Shared Uniswap v4 state and internal helpers (swaps + LP) to be composed into higher-level routers.
abstract contract UniswapV4Module {
    using PoolIdLibrary for PoolKey;

    /// @dev Canonical pool configuration for this strategy.
    PoolKey internal _uniPoolKey;
    PoolId internal _uniPoolId;
    int24 internal _uniDefaultTickLower;
    int24 internal _uniDefaultTickUpper;

    Miniv4SwapRouter public swapRouter;
    IPositionManager public positionManager;
    IPermit2 public immutable permit2;

    constructor(address _swapRouter, address _positionManager) {
        if (_swapRouter == address(0) || _positionManager == address(0)) {
            revert("ZeroAddress");
        }

        swapRouter = Miniv4SwapRouter(payable(_swapRouter));
        positionManager = IPositionManager(_positionManager);
    }

    /// @notice Pure liquidity preview for given token amounts with current pool price and default tick range.
    function previewLiquidity(
        uint256 amount0ForLp,
        uint256 amount1ForLp
    ) external view returns (uint128) {
        return _computeLiquidityFromAmounts(amount0ForLp, amount1ForLp);
    }

    /// @dev Uses borrowed `borrowAsset` to:
    ///      1) Swap into the target token0/token1 composition for the v4 pool.
    ///      2) Mint an LP position owned by `vault`.
    function _enterUniswapV4Position(
        address vault,
        address borrowAsset,
        uint256 borrowedAmount
    )
        internal
        returns (
            uint256 tokenId,
            uint256 spent0,
            uint256 spent1,
            uint256 amount0ForLp,
            uint256 amount1ForLp
        )
    {
        if (borrowedAmount == 0) {
            return (0, 0, 0, 0, 0);
        }

        (address token0, address token1) = _getPoolTokens();

        // 1) Rebalance borrowed asset into LP-ready token0/token1 amounts.
        (amount0ForLp, amount1ForLp) = _swapForLpComposition(
            borrowAsset,
            borrowedAmount,
            token0,
            token1
        );

        if (amount0ForLp == 0 && amount1ForLp == 0) {
            return (0, 0, 0, 0, 0);
        }

        // 2) Compute max liquidity supported by these amounts at current price and tick range.
        uint128 liq128 = _computeLiquidityFromAmounts(
            amount0ForLp,
            amount1ForLp
        );

        if (liq128 == 0) {
            return (0, 0, 0, 0, 0);
        }

        // 3) Cast into uint128 bounds for PositionManager.
        uint128 amount0Max = uint128(amount0ForLp);
        uint128 amount1Max = uint128(amount1ForLp);
        require(uint256(amount0Max) == amount0ForLp, "amount0 overflow");
        require(uint256(amount1Max) == amount1ForLp, "amount1 overflow");

        // 4) Actually mint LP position for the vault as owner.

        _ensurePermit2Approval(token0);
        _ensurePermit2Approval(token1);
        (tokenId, spent0, spent1) = _provideLiquidityForVault(
            uint256(liq128),
            amount0Max,
            amount1Max,
            vault
        );
    }

    /// @dev 1. Remove the entire LP position owned by `vault`.
    ///      2. Swap everything back into `borrowAsset` so it can be used to repay Aave.
    function _exitUniswapV4PositionAndSwapToBorrow(
        address vault,
        address borrowAsset,
        uint256 tokenId
    ) internal returns (uint256 borrowAmountOut) {
        // 0) Guard: ensure vault actually owns this position (PositionManager is ERC721).
        if (IERC721(address(positionManager)).ownerOf(tokenId) != vault) {
            revert("NotVaultOwner");
        }

        // 1) Read current liquidity.
        uint128 liq = positionManager.getPositionLiquidity(tokenId);
        if (liq == 0) revert("NoLiquidity");

        // 2) PoolKey for this module.
        PoolKey memory key = _getPoolKey();

        // 3) Remove all liquidity, routing tokens to this router.
        (uint256 received0, uint256 received1) = _removeLiquidityForVault(
            key,
            vault,
            tokenId,
            uint256(liq),
            0,
            0,
            address(this)
        );

        // 4) Normalize everything into `borrowAsset`.
        (address token0, address token1) = _getPoolTokens();

        if (borrowAsset != token0 && borrowAsset != token1) {
            revert("BorrowAssetNotInPool");
        }

        // For the token equal to `borrowAsset`, keep as-is.
        // The other leg is swapped into `borrowAsset`.
        if (borrowAsset == token0) {
            borrowAmountOut = received0;

            // token1을 받았으면 token0 swap
            if (received1 > 0) {
                // token1 -> token0 : zeroForOne = false
                uint256 swapped = _swapSingleExactIn(
                    key,
                    false,
                    token1,
                    received1
                );
                borrowAmountOut += swapped;
            }
        } else {
            borrowAmountOut = received1;

            if (received0 > 0) {
                // token0 -> token1 zeroForOne = true
                uint256 swapped = _swapSingleExactIn(
                    key,
                    true,
                    token0,
                    received0
                );

                borrowAmountOut += swapped;
            }
        }
    }

    /// @dev Grants effectively-unlimited approval via Permit2 for a given token toward PositionManager.
    function _ensurePermit2Approval(address token) internal {
        uint160 maxAmount = type(uint160).max;
        uint48 maxExpiry = type(uint48).max;

        IPermit2(permit2).approve(
            token,
            address(positionManager), // spender: PositionManager
            maxAmount,
            maxExpiry
        );
    }

    /// @dev Rebalances borrowedAmount of `borrowAsset` into a token0/token1 split
    ///      following the pool composition, for LP minting.
    function _swapForLpComposition(
        address borrowAsset,
        uint256 borrowedAmount,
        address token0,
        address token1
    ) internal returns (uint256 amount0ForLp, uint256 amount1ForLp) {
        // TODO: MiniV4SwapRouter / PoolManager 기반 스왑 로직

        //
        if (borrowedAmount == 0) {
            return (0, 0);
        }

        // Ensure the borrowed asset is actually part of the pool.
        if (borrowAsset != token0 && borrowAsset != token1) {
            revert("Borrow asset not in pool");
        }

        bool zeroForOne = (borrowAsset == token0);
        uint256 half = borrowedAmount / 2;

        uint128 half128 = uint128(half);
        require(uint256(half128) == half, "Amount too big");

        PoolKey memory key = _getPoolKey();

        uint256 amountOut = _swapSingleExactIn(
            key,
            zeroForOne,
            borrowAsset,
            half
        );

        if (zeroForOne) {
            // token0 -> token1
            amount0ForLp = borrowedAmount - half;
            amount1ForLp = amountOut;
        } else {
            // token1 -> token0
            amount0ForLp = amountOut;
            amount1ForLp = borrowedAmount - half;
        }
    }

    /// @dev Uses this router's token0/token1 balance to provide liquidity through PositionManager.
    ///      `recipient` (vault) becomes the owner of the newly minted position.
    function _provideLiquidityForVault(
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address recipient
    ) internal returns (uint256 tokenId, uint256 spent0, uint256 spent1) {
        address provider = address(this);

        PoolKey memory key = _getPoolKey();
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);
        (int24 tickLower, int24 tickUpper) = _getDefaultTickRange();

        // 1) Approve PositionManager for the exact max amounts we may spend.
        if (amount0Max > 0) {
            IERC20(t0).approve(address(positionManager), 0);
            IERC20(t0).approve(address(positionManager), uint256(amount0Max));
        }
        if (amount1Max > 0) {
            IERC20(t1).approve(address(positionManager), 0);
            IERC20(t1).approve(address(positionManager), uint256(amount1Max));
        }

        // 2) Action sequence: MINT_POSITION, then SETTLE_PAIR.
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // 3) Parameters for each action.
        bytes[] memory params = new bytes[](2);
        // MINT_POSITION
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            recipient,
            bytes("")
        );
        // SETTLE_PIAR
        params[1] = abi.encode(key.currency0, key.currency1);

        // 4) Track balances and nextTokenId to infer spent amounts and tokenId.
        uint256 beforeId = positionManager.nextTokenId();
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 300
        );

        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;

        // Any leftover router balances stay as is and can be used by later operations.
        uint256 routerBal0 = IERC20(t0).balanceOf(address(this));
        uint256 routerBal1 = IERC20(t1).balanceOf(address(this));
    }

    /// @dev Burns an LP position via PositionManager.modifyLiquidities and
    ///      sends all underlying token0/token1 to `recipient`.
    function _removeLiquidityForVault(
        PoolKey memory key,
        address owner,
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Min,
        uint128 amount1Min,
        address recipient
    ) internal returns (uint256 received0, uint256 received1) {
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);

        // 1) actions (DECREASE_LIQUIDITY, TAKE_PAIR)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        // 2) params
        bytes[] memory params = new bytes[](2);

        // DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId,
            liquidity,
            amount0Min,
            amount1Min,
            bytes("")
        );

        // TAKE_PAIR
        params[1] = abi.encode(key.currency0, key.currency1, recipient);

        uint256 bal0Before = IERC20(t0).balanceOf(recipient);
        uint256 bal1Before = IERC20(t1).balanceOf(recipient);

        // Call PositionManager.modifyLiquidites
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 300
        );

        //
        uint256 bal0After = IERC20(t0).balanceOf(recipient);
        uint256 bal1After = IERC20(t1).balanceOf(recipient);

        received0 = bal0After - bal0Before;
        received1 = bal1After - bal1Before;
    }

    /// @dev Returns the canonical PoolKey for this module.
    function _getPoolKey() internal view returns (PoolKey memory key) {
        key = _uniPoolKey;
    }

    /// @notice Human-readable v4 pool configuration (for front-ends / tooling).
    function getUniswapV4PoolConfig()
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickSpacing,
            int24 defaultTickLower,
            int24 defaultTickUpper
        )
    {
        token0 = Currency.unwrap(_uniPoolKey.currency0);
        token1 = Currency.unwrap(_uniPoolKey.currency1);
        fee = _uniPoolKey.fee;
        tickSpacing = _uniPoolKey.tickSpacing;
        defaultTickLower = _uniDefaultTickLower;
        defaultTickUpper = _uniDefaultTickUpper;
    }

    /// @dev Convenience for accessing underlying ERC20 addresses of the configured pool.
    function _getPoolTokens()
        internal
        view
        returns (address token0, address token1)
    {
        token0 = Currency.unwrap(_uniPoolKey.currency0);
        token1 = Currency.unwrap(_uniPoolKey.currency1);
    }

    /// @dev Returns the default tick range used by this strategy.
    function _getDefaultTickRange()
        internal
        view
        returns (int24 lower, int24 upper)
    {
        return (_uniDefaultTickLower, _uniDefaultTickUpper);
    }

    /// @dev Sets the canonical v4 pool config and derived internal state for this module.
    function _setUniswapV4PoolConfig(
        PoolKey memory key,
        int24 defaultTickLower,
        int24 defaultTickUpper
    ) internal {
        _uniPoolKey = key;
        _uniPoolId = key.toId();
        _uniDefaultTickLower = defaultTickLower;
        _uniDefaultTickUpper = defaultTickUpper;
    }

    /// @dev Reads the current sqrtPriceX96 from the configured pool.
    function _getSqrtPriceX96() internal view returns (uint160) {
        IPoolManager manager = swapRouter.poolManager();
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(
            manager,
            _uniPoolId
        );

        return sqrtPriceX96;
    }

    /// @dev Computes the maximum liquidity obtainable for the given amounts,
    ///      under current pool price and default tick range.
    function _computeLiquidityFromAmounts(
        uint256 amount0ForLp,
        uint256 amount1ForLp
    ) internal view returns (uint128 liquidity) {
        if (amount0ForLp == 0 || amount1ForLp == 0) {
            return 0;
        }

        uint160 sqrtPriceX96 = _getSqrtPriceX96();

        (int24 tickLower, int24 tickUpper) = _getDefaultTickRange();

        // 3) tick -> sqrtPriceA/B
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        // 4) LiquidityAmounts lib -> cal max liquidity
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            amount0ForLp,
            amount1ForLp
        );
    }

    /// @dev Single-pool exact-input swap via Miniv4SwapRouter using the configured pool key.

    function _swapSingleExactIn(
        PoolKey memory key,
        bool zeroForOne,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        uint128 amt128 = uint128(amountIn);
        require(uint256(amt128) == amountIn, "amount overflow");

        IERC20(tokenIn).approve(address(swapRouter), 0);
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amt128,
                amountOutMin: 0,
                hookData: bytes("")
            });

        amountOut = swapRouter.swapExactInputSingle(params);
    }

    /// @dev Pure view helper:
    ///      "If we removed all liquidity for this tokenId right now,
    ///       how much token0/token1 would we get back?"
    ///
    ///      - Uses this module's default tick range.
    ///      - Assumes positions were minted by this router with that range.
    function _previewLpWithdrawAmounts(
        uint256 tokenId
    )
        internal
        view
        returns (
            PoolKey memory key,
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        )
    {
        key = _getPoolKey();
        (token0, token1) = _getPoolTokens();

        uint160 sqrtPriceX96 = _getSqrtPriceX96();

        (int24 tickLower, int24 tickUpper) = _getDefaultTickRange();

        // 4) Read current LP liquidity for this position.
        uint128 liq = positionManager.getPositionLiquidity(tokenId);
        if (liq == 0) {
            return (key, token0, token1, 0, 0);
        }

        // 5) Use our math helper to simulate a full withdraw.
        (amount0, amount1) = UniswapV4LiquidityPreview.previewRemoveLiquidity(
            sqrtPriceX96,
            tickLower,
            tickUpper,
            liq
        );
    }

    /// @dev Collects accumulated fees for a given tokenId via PositionManager,
    ///      without changing position liquidity.
    function _collectFees(
        PoolKey memory key,
        address owner,
        uint256 tokenId,
        address recipient
    ) internal returns (uint256 collected0, uint256 collected1) {
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);

        uint256 bal0Before = IERC20(t0).balanceOf(recipient);
        uint256 bal1Before = IERC20(t1).balanceOf(recipient);

        // actions : [DECREASE_LIQUIDITY(0) + TAKE_PAIR]
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        // params
        bytes[] memory params = new bytes[](2);

        // DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId,
            uint128(0),
            uint128(0),
            uint128(0),
            bytes("")
        );

        // TAKE_PAIR
        params[1] = abi.encode(t0, t1, recipient);

        // PositionManager 호출
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        // 수수료 계산
        uint256 bal0After = IERC20(t0).balanceOf(recipient);
        uint256 bal1After = IERC20(t1).balanceOf(recipient);

        collected0 = bal0After - bal0Before;
        collected1 = bal1After - bal1Before;
    }
}
