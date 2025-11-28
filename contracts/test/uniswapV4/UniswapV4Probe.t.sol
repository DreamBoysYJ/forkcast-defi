// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title UniswapV4ProbeTest
 * @notice Low-level probe tests for Uniswap v4 on Sepolia.
 *         Scope:
 *           - PoolManager.initialize for AAVE/WBTC pool
 *           - PositionManager.modifyLiquidities add/remove flows
 *           - Fee collection vs. liquidity changes
 *           - MiniV4SwapRouter integration + basic revert guards
 */

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {
    IPositionManager
} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

import {
    IERC20
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {PositionInfo} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";

import {Miniv4SwapRouter} from "../../src/uniswapV4/Miniv4SwapRouter.sol";

contract UniswapV4ProbeTest is Test {
    using PoolIdLibrary for PoolKey;

    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IPermit2 public permit2;

    Miniv4SwapRouter public router;

    address public userAddr;
    address public AAVE;
    address public WBTC;

    function setUp() public {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);

        userAddr = vm.envAddress("USER_ADDRESS");
        AAVE = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        WBTC = vm.envAddress("WBTC_UNDERLYING_SEPOLIA");

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        poolManager = IPoolManager(poolManagerAddr);
        address positionMangerAddr = vm.envAddress("POSITION_MANAGER");
        positionManager = IPositionManager(positionMangerAddr);
        address permit2Addr = vm.envAddress("PERMIT2");
        permit2 = IPermit2(permit2Addr);

        _deployRouter();
    }

    // ============================ Success cases ============================

    /// @dev Only checks that pool initialization succeeds for the AAVE/WBTC pair.
    function test_InitPool_Succeeds() public {
        // 1) AAVE/WBTC 풀 초기화
        (PoolKey memory key, int24 initTick) = _initPool();
    }

    /// @dev init pool -> add liquidity once -> assert position liquidity.
    function test_ModifyLiquidity_Add_Succeeds() public {
        // 1) 풀 + 유동성 추가 (Liq = 100e18)
        (PoolKey memory key, uint256 tokenId) = _givenPoolWithWideLiquidity();

        // 2) 검증 : Liq 양 확인 Position Manager를 통해 Liquidity 확인
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(liquidity, 100e18, "liquidity must be same as increasement");
    }

    /// @dev init pool -> add liquidity -> remove all liquidity and assert zero.
    function test_ModifyLiquidity_RemoveAll_Succeeds() public {
        // 1) 풀 init
        (PoolKey memory key, int24 initTick) = _initPool();

        // 2) User setUp
        address user = makeAddr("user");
        vm.startPrank(user);
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);
        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);

        uint256 u0Init = IERC20(token0).balanceOf(user);
        uint256 u1Init = IERC20(token1).balanceOf(user);

        // 3) PositionManager - 유동성 공급 (Liq = 100e18, token0 : 100e18, token1 : 100e18 마늠)
        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        uint256 u0Before = IERC20(token0).balanceOf(user);
        uint256 u1Before = IERC20(token1).balanceOf(user);

        // 검증 : Liq 양 확인 Position Manager를 통해 Liquidity 확인
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(liquidity, 100e18, "liquidity must be same as increasement");

        // 4) PositionManager - 유동성 제거

        (uint256 recv0, uint256 recv1) = _removeLiquidity(
            key,
            user,
            tokenId,
            100e18,
            0,
            0,
            user
        );

        uint256 u0After = IERC20(token0).balanceOf(user);
        uint256 u1After = IERC20(token1).balanceOf(user);

        // 5) 검증
        assertGt(recv0 + recv1, 0, "should receive some tokens");
        assertGt(u0After, u0Before, "token0 balance should increase");
        assertGt(u1After, u1Before, "token1 balance should increase");

        // 검증 : Liq 양 확인 Position Manager를 통해 Liquidity 확인
        liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(liquidity, 0, "liquidity must be same as increasement");
    }

    /// @dev init pool -> add liquidity -> remove half and assert half remains.
    function test_ModifyLiquidity_RemoveHalf_Succeeds() public {
        // 1) 풀 init
        (PoolKey memory key, int24 initTick) = _initPool();

        // 2) User setUp
        address user = makeAddr("user");
        vm.startPrank(user);
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);
        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);

        uint256 u0Init = IERC20(token0).balanceOf(user);
        uint256 u1Init = IERC20(token1).balanceOf(user);

        // 3) PositionManager - 유동성 공급 (Liq = 1e18, token0 : 100e18, token1 : 100e18 마늠)
        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        uint256 u0Before = IERC20(token0).balanceOf(user);
        uint256 u1Before = IERC20(token1).balanceOf(user);

        // 검증 : Liq 양 확인 Position Manager를 통해 Liquidity 확인
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(liquidity, 100e18, "liquidity must be same as increasement");

        // 4) PositionManager - 유동성 제거

        (uint256 recv0, uint256 recv1) = _removeLiquidity(
            key,
            user,
            tokenId,
            100e18 / 2,
            0,
            0,
            user
        );

        uint256 u0After = IERC20(token0).balanceOf(user);
        uint256 u1After = IERC20(token1).balanceOf(user);

        // 5) 검증
        assertGt(recv0 + recv1, 0, "should receive some tokens");
        assertGt(u0After, u0Before, "token0 balance should increase");
        assertGt(u1After, u1Before, "token1 balance should increase");

        liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(
            liquidity,
            100e18 / 2,
            "liquidity must be same as increasement"
        );
    }

    /// @dev init pool -> add liquidity -> trigger swap -> collect only fees (no liquidity change).
    function test_CollectFee_Succeeds() public {
        // 1) 풀 init
        (PoolKey memory key, ) = _initPool();

        // 2) LP 세팅 + 유동성 공급
        address user = makeAddr("user");
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);

        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);
        IERC20(token1).approve(address(router), type(uint256).max);

        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        uint128 liqBefore = positionManager.getPositionLiquidity(tokenId);
        vm.stopPrank();

        // 3) swap 한 번 일으켜서 수수료 발생
        {
            address swapper = makeAddr("swapper");
            deal(token0, swapper, 100e18);
            vm.startPrank(swapper);

            IERC20(token0).approve(address(router), type(uint256).max);

            Miniv4SwapRouter.ExactInputSingleParams
                memory params = Miniv4SwapRouter.ExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: true,
                    amountIn: 50e18,
                    amountOutMin: 0,
                    hookData: bytes("")
                });

            router.swapExactInputSingle(params);
            vm.stopPrank();
        }

        // 4) LP가 수수료만 수취
        vm.startPrank(user);

        uint256 u0BeforeCollect = IERC20(token0).balanceOf(user);
        uint256 u1BeforeCollect = IERC20(token1).balanceOf(user);

        (uint256 fee0, uint256 fee1) = _collectFees(key, user, tokenId, user);

        uint256 u0AfterCollect = IERC20(token0).balanceOf(user);
        uint256 u1AfterCollect = IERC20(token1).balanceOf(user);
        uint128 liqAfter = positionManager.getPositionLiquidity(tokenId);

        console2.log("Fee Collected token0 : ", fee0);
        console2.log("Fee Collected token1 : ", fee1);

        // 검증
        assertGt(fee0 + fee1, 0, "LP should earn some fees after swap");
        assertEq(
            u0AfterCollect,
            u0BeforeCollect + fee0,
            "token0 balance mismatch"
        );
        assertEq(
            u1AfterCollect,
            u1BeforeCollect + fee1,
            "token1 balance mismatch"
        );
        assertEq(
            liqAfter,
            liqBefore,
            "liquidity should not change when only collecting fees"
        );

        vm.stopPrank();
    }

    /// @dev init pool -> add liquidity -> trigger swap -> remove all liquidity (principal + fees).
    function test_ModifyLiquidity_RemoveAll_WithFee_Succeeds() public {
        // 1) 풀 init
        (PoolKey memory key, ) = _initPool();

        // 2) LP 세팅 + 유동성 공급
        address user = makeAddr("user");
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);

        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);
        IERC20(token1).approve(address(router), type(uint256).max);

        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        uint128 liqBefore = positionManager.getPositionLiquidity(tokenId);
        vm.stopPrank();

        // 3) swap 한 번 일으켜서 수수료 발생 (token0 -> token1)
        {
            address swapper = makeAddr("swapper");
            deal(token0, swapper, 100e18);
            vm.startPrank(swapper);

            IERC20(token0).approve(address(router), type(uint256).max);

            Miniv4SwapRouter.ExactInputSingleParams
                memory params = Miniv4SwapRouter.ExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: true,
                    amountIn: 50e18,
                    amountOutMin: 0,
                    hookData: bytes("")
                });

            router.swapExactInputSingle(params);
            vm.stopPrank();
        }

        // uint256 u0After = IERC20(token0).balanceOf(user);
        // uint256 u1After = IERC20(token1).balanceOf(user);

        // 4) PositionManager - 유동성 전체 제거
        vm.startPrank(user);

        (uint256 recv0, uint256 recv1) = _removeLiquidity(
            key,
            user,
            tokenId,
            100e18,
            0,
            0,
            user
        );

        uint256 u0After = IERC20(token0).balanceOf(user);
        uint256 u1After = IERC20(token1).balanceOf(user);

        // 5) 검증
        console2.log("TOKEN 0 after RemoveAll", u0After / 1e18);
        console2.log("TOKEN 1 after RemoveAll", u1After / 1e18);
        // assertGt(recv0 + recv1, 0, "should receive some tokens");
        // assertGt(u0After, u0Before, "token0 balance should increase");
        // assertGt(u1After, u1Before, "token1 balance should increase");

        // 검증 : Liq 양 확인 Position Manager를 통해 Liquidity 확인
        uint128 liquidity = positionManager.getPositionLiquidity(tokenId);
        assertEq(liquidity, 0, "liquidity must be same as increasement");
        vm.stopPrank();
    }

    // ============================ Revert / guard cases ============================

    /// @dev Swapping against a non-initialized pool must revert.
    function test_ExactInputSingle_Revert_WhenPoolNotInitialized() public {
        // 1) User setup
        address user = makeAddr("user");
        vm.startPrank(user);

        deal(WBTC, user, 1_000e18);
        deal(AAVE, user, 1_000e18);
        IERC20(WBTC).approve(address(router), type(uint256).max);
        IERC20(AAVE).approve(address(router), type(uint256).max);

        // 2) Build PoolKey
        PoolKey memory key = _buildPoolKey(
            AAVE,
            WBTC,
            3000,
            60,
            IHooks(address(0))
        );

        // 3) call SwapExactInputSingle through MiniV4SwapRoute
        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: 100e18,
                amountOutMin: 0,
                hookData: bytes("")
            });

        // 4) expect revert

        vm.expectRevert();
        router.swapExactInputSingle(params);
    }

    /// @dev Initializing with currency0 >= currency1 should revert (wrong ordering).
    function test_InitPool_Revert_WhenCurrenciesOutOfOrder() public {
        // 1) 토큰 주소 정렬
        address token0;
        address token1;

        // 반대로 정렬
        if (AAVE < WBTC) {
            token0 = WBTC;
            token1 = AAVE;
        } else {
            token0 = AAVE;
            token1 = WBTC;
        }

        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);

        // 2) PoolKey 생성
        // fee-3000, tickSpacing - 60, hooks X
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        // 3) 초기 가격 설정 (1:1)
        uint160 sqrtPriceX96 = uint160(1) << 96;

        // 4) init 시도
        vm.expectRevert();
        poolManager.initialize(key, sqrtPriceX96);
    }

    /// @dev Non-owner attempting to remove liquidity must revert.
    function test_ModifyLiquidity_Remove_Revert_WhenNotOwner() public {
        // 1) 풀 init
        (PoolKey memory key, int24 initTick) = _initPool();

        // 2) User setUp
        address user = makeAddr("user");
        vm.startPrank(user);
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);
        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);

        // 3) PositionManager - 유동성 공급 (Liq = 100e18, token0 : 100e18, token1 : 100e18 마늠)
        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        vm.stopPrank();

        // 4) hacker : PositionManager - 유동성 제거
        address hacker = makeAddr("hacker");
        vm.startPrank(hacker);

        vm.expectRevert();
        (uint256 recv0, uint256 recv1) = _removeLiquidity(
            key,
            hacker,
            tokenId,
            100e18,
            0,
            0,
            hacker
        );
    }

    /// @dev Removing more liquidity than the position owns must revert.
    function test_ModifyLiquidity_Remove_Revert_WhenExceedsLiquidity() public {
        // 1) 풀 init
        (PoolKey memory key, ) = _initPool();

        // 2) User setup
        address user = makeAddr("user");
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        deal(token0, user, 1_000e18);
        deal(token1, user, 1_000e18);

        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);

        // 3) 유동성 100e18 공급
        (uint256 tokenId, , ) = _addLiquidity(
            key,
            user,
            -887220,
            887220,
            100e18,
            100e18,
            100e18,
            user
        );

        uint128 liq = positionManager.getPositionLiquidity(tokenId);
        assertEq(liq, 100e18, "liquidity must be 100e18");

        // 4) 보유량(100e18) 초과인 200e18 제거 시도 → SafeCastOverflow 리버트 기대
        vm.expectRevert(); // 필요하면 SafeCastOverflow.selector 로 바꿀 수 있음
        _removeLiquidityRaw(key, tokenId, 200e18, user);

        vm.stopPrank();
    }

    // ============================ Helper functions ============================

    function _deployRouter() internal {
        router = new Miniv4SwapRouter(address(poolManager));
    }

    /// @dev init pool and immediately add a wide-range liquidity position.
    function _givenPoolWithWideLiquidity()
        internal
        returns (PoolKey memory key, uint256 tokenId)
    {
        (key, ) = _initPool();
        address lp = makeAddr("lp");
        tokenId = _addLiquidityWideDefault(key, lp);
    }

    /// @dev Canonical AAVE/WBTC PoolKey (fee 3000, tickSpacing 60, no hooks).
    function _buildAaveWbtcPoolKey()
        internal
        view
        returns (PoolKey memory key)
    {
        // 1) 토큰 주소 정렬
        address token0;
        address token1;

        if (AAVE < WBTC) {
            token0 = AAVE;
            token1 = WBTC;
        } else {
            token0 = WBTC;
            token1 = AAVE;
        }

        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);

        // 2) PoolKey
        // fee-3000, tickSpacing - 60, hooks X
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    /// @dev Initialize AAVE/WBTC pool at 1:1 and return PoolKey + initial tick.
    function _initPool() internal returns (PoolKey memory key, int24 initTick) {
        key = _buildAaveWbtcPoolKey();

        // 3) 초기 가격 설정 (1:1)
        uint160 sqrtPriceX96 = uint160(1) << 96;

        // 4) init
        initTick = poolManager.initialize(key, sqrtPriceX96);

        console2.log("Initialized tick : ", initTick);
        assertApproxEqAbs(
            initTick,
            0,
            10,
            "init tick should be near 0 for 1:1 price"
        );
    }

    /// @dev Add liquidity via PositionManager, using Permit2 for token approvals.
    function _addLiquidity(
        PoolKey memory key,
        address provider,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address recipient
    ) internal returns (uint256 tokenId, uint256 spent0, uint256 spent1) {
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);

        // 1) Permit2 경유 apprvoe
        vm.startPrank(provider);
        IERC20(t0).approve(address(permit2), type(uint256).max);
        IERC20(t1).approve(address(permit2), type(uint256).max);

        uint160 max160 = type(uint160).max;
        uint48 neverExpire = type(uint48).max;
        permit2.approve(t0, address(positionManager), max160, neverExpire);
        permit2.approve(t1, address(positionManager), max160, neverExpire);

        // 2) 액션 구성 (MINT_POSITION, SETTLE_PAIR)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // 3) params 구성
        bytes[] memory params = new bytes[](2);
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
        params[1] = abi.encode(key.currency0, key.currency1);

        // 4) PositionManager 호출
        uint256 beforeId = positionManager.nextTokenId();
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        uint256 afterId = positionManager.nextTokenId();
        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);
        vm.stopPrank();

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;
    }

    /// @dev Decrease liquidity and immediately TAKE_PAIR to the recipient.
    function _removeLiquidity(
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

        // 3) before 잔액
        uint256 bal0Before = IERC20(t0).balanceOf(recipient);
        uint256 bal1Before = IERC20(t1).balanceOf(recipient);

        // owner -> PositionManager 호출
        vm.startPrank(owner);
        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );
        vm.stopPrank();

        // 5) after 잔액과 비교
        uint256 bal0After = IERC20(t0).balanceOf(recipient);
        uint256 bal1After = IERC20(t1).balanceOf(recipient);

        received0 = bal0After - bal0Before;
        received1 = bal1After - bal1Before;
    }

    /// @dev Wide-range, large-liquidity helper: [-887220, 887220], L=100e18.
    function _addLiquidityWideDefault(
        PoolKey memory key,
        address provider
    ) internal returns (uint256 tokenId) {
        int24 tickLower = -887220;
        int24 tickUpper = 887220;
        (tokenId, , ) = _addLiquidity(
            key,
            provider,
            tickLower,
            tickUpper,
            100e18,
            uint128(100e18),
            uint128(100e18),
            provider
        );
    }

    /// @dev Collect only fees (no liquidity change) via a zero-liquidity DECREASE + TAKE_PAIR.
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

    /// @dev Decode raw PositionInfo into (poolId, tickLower, tickUpper, hasSubscriber).
    function _decodePositionInfo(
        PositionInfo info
    )
        internal
        pure
        returns (
            bytes25 poolId,
            int24 tickLower,
            int24 tickUpper,
            bool hasSubscriber
        )
    {
        uint256 raw = PositionInfo.unwrap(info);

        // 1) hasSubscriber (하위 8비트)
        uint8 hasSubFlag = uint8(raw & 0xFF);
        hasSubscriber = hasSubFlag != 0;

        // 2) tickLower (다음 24비트)
        uint256 lowerBits = (raw >> 8) & ((1 << 24) - 1);
        tickLower = int24(int256(lowerBits));

        // 3) tickLower (그 다음 24비트)
        uint256 upperBits = (raw >> (8 + 24)) & ((1 << 24) - 1);
        tickUpper = int24(int256(upperBits));

        // 4) poolId (상위 200비트 → bytes25)
        uint256 poolBits = raw >> (8 + 24 + 24); // = raw >> 56
        // 200비트 → bytes25로 캐스팅
        poolId = bytes25(bytes32(poolBits)); // 테스트용이면 이 정도면 충분
    }

    /// @dev Canonical PoolKey builder from two token addresses.
    function _buildPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    ) internal pure returns (PoolKey memory key) {
        address currency0;
        address currency1;

        if (tokenA < tokenB) {
            currency0 = tokenA;
            currency1 = tokenB;
        } else {
            currency0 = tokenB;
            currency1 = tokenA;
        }

        key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks
        });
    }

    /// @dev Raw DECREASE_LIQUIDITY + TAKE_PAIR without balance assertions (used for revert tests).

    function _removeLiquidityRaw(
        PoolKey memory key,
        uint256 tokenId,
        uint256 liquidity,
        address recipient
    ) internal {
        // actions: DECREASE_LIQUIDITY + TAKE_PAIR
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        // DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId,
            liquidity,
            uint128(0),
            uint128(0),
            bytes("")
        );

        // TAKE_PAIR
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);
        params[1] = abi.encode(t0, t1, recipient);

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );
    }
}
