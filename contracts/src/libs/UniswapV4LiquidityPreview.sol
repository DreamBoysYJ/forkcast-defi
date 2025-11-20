// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";

library UniswapV4LiquidityPreview {
    /// @notice 현재 풀 상태(sqrtPriceX96) 기준으로,
    ///         주어진 liquidity, tick 구간을 전부 제거하면
    ///         얼마의 token0, token1을 받게 되는지 "미리보기" 계산
    ///
    /// @param sqrtPriceX96  현재 풀 sqrt 가격
    /// @param tickLower     포지션의 하한 틱
    /// @param tickUpper     포지션의 상한 틱
    /// @param liquidity     포지션이 가진 유동성
    /// @return amount0      이론상 받게 되는 token0 양 (round down)
    /// @return amount1      이론상 받게 되는 token1 양 (round down)
    function previewRemoveLiquidity(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) {
            return (0, 0);
        }

        // tick -> sqrtPrice
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        // A < B sorting
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        //
        if (sqrtPriceX96 <= sqrtPriceAX96) {
            // 전체 구간이 현재 가격보다 위 -> 전부 token 0
            amount0 = SqrtPriceMath.getAmount0Delta(
                sqrtPriceAX96,
                sqrtPriceBX96,
                liquidity,
                false
            );
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            // 현재 가격이 구간 내 -> token0 + token1
            amount0 = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                sqrtPriceBX96,
                liquidity,
                false
            );
            amount1 = SqrtPriceMath.getAmount1Delta(
                sqrtPriceAX96,
                sqrtPriceX96,
                liquidity,
                false
            );
        } else {
            // 전체 구간이 현재 가격보다 아래 -> 전부 token1
            amount1 = SqrtPriceMath.getAmount1Delta(
                sqrtPriceAX96,
                sqrtPriceBX96,
                liquidity,
                false
            );
        }
    }
}
