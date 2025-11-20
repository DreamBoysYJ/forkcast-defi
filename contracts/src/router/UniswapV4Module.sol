// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/console2.sol";

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

/// @dev Uniswap v4 관련 상태/내부 로직을 넣을 모듈.
/// 지금은 비워두고, 나중에 swap + LP 로직을 여기다 추가하면 됨.
abstract contract UniswapV4Module {
    using PoolIdLibrary for PoolKey;

    PoolKey internal _uniPoolKey;
    PoolId internal _uniPoolId;
    int24 internal _uniDefaultTickLower;
    int24 internal _uniDefaultTickUpper;

    Miniv4SwapRouter public swapRouter;
    IPositionManager public positionManager;
    IPermit2 public immutable permit2;

    // 예: 나중에 이런 것들이 들어올 예정
    // IPoolManager public poolManager;
    // IPositionManager public positionManager;

    constructor(address _swapRouter, address _positionManager) {
        if (_swapRouter == address(0) || _positionManager == address(0)) {
            revert("ZeroAddress");
        }

        swapRouter = Miniv4SwapRouter(payable(_swapRouter));
        positionManager = IPositionManager(_positionManager);
    }

    function previewLiquidity(
        uint256 amount0ForLp,
        uint256 amount1ForLp
    ) external view returns (uint128) {
        return _computeLiquidityFromAmounts(amount0ForLp, amount1ForLp);
    }

    /// @dev Aave에서 빌려온 borrowAsset을 사용해
    ///      - 1) v4 풀 구성 비율에 맞게 스왑
    ///      - 2) 금고(vault)를 소유자로 하는 LP 포지션을 만들어 유동성을 공급한다.
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

        // 1) 빌린 자산 스왑 -> LP용 token0/token1 비율로 맞추기
        (amount0ForLp, amount1ForLp) = _swapForLpComposition(
            borrowAsset,
            borrowedAmount,
            token0,
            token1
        );

        if (amount0ForLp == 0 && amount1ForLp == 0) {
            return (0, 0, 0, 0, 0);
        }

        // 2) 현재 토큰 보유 + 현재 가격 + tick 범위 기준 -> liquidity 계산
        uint128 liq128 = _computeLiquidityFromAmounts(
            amount0ForLp,
            amount1ForLp
        );

        if (liq128 == 0) {
            return (0, 0, 0, 0, 0);
        }

        // 3) amount0Max, amount1Max로 캐스팅
        uint128 amount0Max = uint128(amount0ForLp);
        uint128 amount1Max = uint128(amount1ForLp);
        require(uint256(amount0Max) == amount0ForLp, "amount0 overflow");
        require(uint256(amount1Max) == amount1ForLp, "amount1 overflow");

        // 4) 실제 LP 공급 (소유자 vault)

        _ensurePermit2Approval(token0);
        _ensurePermit2Approval(token1);
        (tokenId, spent0, spent1) = _provideLiquidityForVault(
            uint256(liq128),
            amount0Max,
            amount1Max,
            vault
        );
    }

    /// @dev 1. 라우터 - 유저 금고의 LP 전체 제거
    ///      2. 라우터 - Aave에서 borrowAsset을 갚기 위해 swap
    function _exitUniswapV4PositionAndSwapToBorrow(
        address vault,
        address borrowAsset,
        uint256 tokenId
    ) internal returns (uint256 borrowAmountOut) {
        // 0) owner 검증: PositionManager는 ERC721이므로 IERC721으로 캐스팅
        if (IERC721(address(positionManager)).ownerOf(tokenId) != vault) {
            revert("NotVaultOwner");
        }

        // 1) Liquidity 조회
        uint128 liq = positionManager.getPositionLiquidity(tokenId);
        if (liq == 0) revert("NoLiquidity");

        // 2) PoolKey
        PoolKey memory key = _getPoolKey();

        // 3) 전체 LP 제거 -> 수령자 router
        (uint256 received0, uint256 received1) = _removeLiquidityForVault(
            key,
            vault,
            tokenId,
            uint256(liq),
            0,
            0,
            address(this)
        );
        console2.log("LP END token0:::", received0);
        console2.log("LP END token1:::", received1);

        // 4) borrowAsset 기준으로 정리
        (address token0, address token1) = _getPoolTokens();

        if (borrowAsset != token0 && borrowAsset != token1) {
            revert("BorrowAssetNotInPool");
        }

        // LP 제거로 router가 받은 토큰을 기준
        // - borrowAsset은 그대로 더하기
        // - 나머지 토큰 swap -> borrowAsset
        if (borrowAsset == token0) {
            borrowAmountOut = received0;

            // token1을 받았으면 token0 swap
            if (received1 > 0) {
                // token1 -> token 0 : zeroForOne = false
                uint256 swapped = _swapSingleExactIn(
                    key,
                    false,
                    token1,
                    received1
                );
                console2.log("SWAPPED 1 -> 0, :::", swapped);
                borrowAmountOut += swapped;
                console2.log("TOTAL TOKEN AFTER SWAPPED :::", borrowAmountOut);
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
                console2.log("SWAPPED 0 -> 1, :::", swapped);

                borrowAmountOut += swapped;
                console2.log("TOTAL TOKEN AFTER SWAPPED :::", borrowAmountOut);
            }
        }
    }

    function _ensurePermit2Approval(address token) internal {
        // uint160, uint48 범위 맞춰주기
        uint160 maxAmount = type(uint160).max;
        uint48 maxExpiry = type(uint48).max;

        IPermit2(permit2).approve(
            token,
            address(positionManager), // spender: PositionManager
            maxAmount,
            maxExpiry
        );
    }

    /// @dev borrowAsset, borrowedAmount를 받아
    ///      v4 풀의 token0/token1 비율에 맞게 스왑하여
    ///      LP 공급에 사용할 token0/token1 양을 반환한다.
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

        // borrowAsset이 풀 토큰인지 확인
        if (borrowAsset != token0 && borrowAsset != token1) {
            revert("Borrow asset not in pool");
        }

        bool zeroForOne = (borrowAsset == token0);
        uint256 half = borrowedAmount / 2;
        console2.log("Half of Borrow token :::", half);

        uint128 half128 = uint128(half);
        require(uint256(half128) == half, "Amount too big");

        PoolKey memory key = _getPoolKey();

        uint256 amountOut = _swapSingleExactIn(
            key,
            zeroForOne,
            borrowAsset,
            half
        );

        console2.log("Result of Swapped  :::", amountOut);

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

    /// @dev Router(address(this))가 보유한 token0/token1을 사용해
    ///      v4 PositionManager.modifyLiquidities로 유동성을 공급.
    ///      recipient(=vault)를 포지션 소유자로 설정.
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

        // 1) Router -> PositionManager approve
        if (amount0Max > 0) {
            IERC20(t0).approve(address(positionManager), 0);
            IERC20(t0).approve(address(positionManager), uint256(amount0Max));
        }
        if (amount1Max > 0) {
            IERC20(t1).approve(address(positionManager), 0);
            IERC20(t1).approve(address(positionManager), uint256(amount1Max));
        }

        // 2) Actions (MINT_POSITION, SETTLE_PAIR)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // 3) params 구성
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

        // 4) before/after 잔고, tokenId 캡처
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
        console2.log("token0 Provided in Pool :::", spent0);
        console2.log("token1 Provided in Pool :::", spent1);

        uint256 routerBal0 = IERC20(t0).balanceOf(address(this));
        uint256 routerBal1 = IERC20(t1).balanceOf(address(this));

        console2.log("ROUTER HAS :::: token0", routerBal0);
        console2.log("ROUTER HAS :::: token1", routerBal1);
    }

    /// @dev v4 PositionManager.modifyLiquidities로 유동성을 전체 해제
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

    function _getPoolKey() internal view returns (PoolKey memory key) {
        key = _uniPoolKey;
    }

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

    function _getPoolTokens()
        internal
        view
        returns (address token0, address token1)
    {
        token0 = Currency.unwrap(_uniPoolKey.currency0);
        token1 = Currency.unwrap(_uniPoolKey.currency1);
    }

    function _getDefaultTickRange()
        internal
        view
        returns (int24 lower, int24 upper)
    {
        return (_uniDefaultTickLower, _uniDefaultTickUpper);
    }

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

    function _getSqrtPriceX96() internal view returns (uint160) {
        IPoolManager manager = swapRouter.poolManager();
        (uint160 sqrtPriceX96, , , ) = StateLibrary.getSlot0(
            manager,
            _uniPoolId
        );

        return sqrtPriceX96;
    }

    function _computeLiquidityFromAmounts(
        uint256 amount0ForLp,
        uint256 amount1ForLp
    ) internal view returns (uint128 liquidity) {
        if (amount0ForLp == 0 || amount1ForLp == 0) {
            return 0;
        }

        // 1) 현재 풀 가격
        uint160 sqrtPriceX96 = _getSqrtPriceX96();

        // 2) 공유하는 tick 범위
        (int24 tickLower, int24 tickUpper) = _getDefaultTickRange();

        // 3) tick -> sqrtPriceA/B
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);

        // 4) LiquidityAmounts 라이브러리 -> 최대 liquidity 계산
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            amount0ForLp,
            amount1ForLp
        );
    }

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

    /// @dev 주어진 tokenId에 대해
    ///      "지금 이 순간 LP를 전량 제거하면 token0, token1을 얼마나 받을까?"
    ///      를 시뮬레이션하는 함수.
    ///
    ///      - tickLower / tickUpper 는 Router가 세팅한 기본 범위(_getDefaultTickRange)를 사용
    ///      - 이 Router가 민팅한 포지션만 대상으로 쓴다는 가정(현재 설계와 일치)
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
        // 1) 이 Router가 들고 있는 풀 설정 기준
        key = _getPoolKey();
        (token0, token1) = _getPoolTokens();

        // 2) 현재 풀 가격
        uint160 sqrtPriceX96 = _getSqrtPriceX96();

        // 3) 이 Router가 사용하는 기본 tick 범위
        (int24 tickLower, int24 tickUpper) = _getDefaultTickRange();

        // 4) 해당 포지션의 유동성 읽기
        uint128 liq = positionManager.getPositionLiquidity(tokenId);
        if (liq == 0) {
            // 리턴 타입 맞춰서 깔끔하게 반환
            return (key, token0, token1, 0, 0);
        }

        // 5) 우리가 만든 수학 라이브러리로
        //    "이 LP 전량 제거 시 받을 token0/token1 양" 시뮬레이션
        (amount0, amount1) = UniswapV4LiquidityPreview.previewRemoveLiquidity(
            sqrtPriceX96,
            tickLower,
            tickUpper,
            liq
        );
    }

    /// @dev PositionManager 통해 수수료만 얻기
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
