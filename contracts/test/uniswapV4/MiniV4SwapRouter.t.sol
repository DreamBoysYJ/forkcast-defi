// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MiniV4SwapRouterTest
 * @notice Integration-style tests for MiniV4SwapRouter on a Sepolia fork.
 *         Covers:
 *          - Happy-path swaps in both directions
 *          - Basic pool bootstrap (initialize + addLiquidity)
 *          - Guards around amountIn, slippage, uninitialized pool, no liquidity,
 *            and unauthorized unlockCallback callers
 */

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
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

contract MiniV4SwapRouterTest is Test {
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

    /// ======================= Success paths =======================

    /// @dev Sanity check: can initialize an AAVE/WBTC pool and mint wide-range LP.
    function test_InitPool_Then_AddLiquidity() public {
        // 1) Initialize AAVE/WBTC pool at 1:1 price
        (PoolKey memory key, int24 initTick) = _initPool();

        // 2) Provide wide-range liquidity
        address lp = makeAddr("lp");
        uint256 tokenId = _addLiquidityWideDefault(key, lp);

        // 3) Validate NFT tick range matches our default full-range config
        PositionInfo info = positionManager.positionInfo(tokenId);
        (, int24 low, int24 up, ) = _decodePositionInfo(info);
        assertEq(low, -887220);
        assertEq(up, 887220);
    }

    /// @dev Happy path: token0 -> token1 swap via MiniV4SwapRouter (zeroForOne = true).

    function test_SwapExactInputSingle_ZeroForOne_Succeeds() public {
        // 1) Bootstrap pool with wide liquidity
        (PoolKey memory key, uint256 tokenId) = _gienPoolWithWideLiquidity();

        // 2) Fund user with token0
        address user = makeAddr("user");
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token0, user, 1_000e18);
        vm.startPrank(user);
        IERC20(token0).approve(address(router), type(uint256).max);

        uint256 u0Before = IERC20(token0).balanceOf(user);
        uint256 u1Before = IERC20(token1).balanceOf(user);

        // 3) Execute swap through MiniV4SwapRouter
        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: uint128(100e18),
                amountOutMin: 0,
                hookData: bytes("")
            });

        uint256 amountOut = router.swapExactInputSingle(params);
        vm.stopPrank();

        assertGt(amountOut, 0, "amountOut should be >0");

        // 4) Assertions: non-zero output, balances move as expected, router has no dust
        assertEq(
            IERC20(token0).balanceOf(user),
            u0Before - 100e18,
            "token0 spent mismatch"
        );
        assertEq(
            IERC20(token1).balanceOf(user),
            u1Before + amountOut,
            "token1 received mismatch"
        );

        assertEq(
            IERC20(token0).balanceOf(address(router)),
            0,
            "router token0 dust"
        );
        assertEq(
            IERC20(token1).balanceOf(address(router)),
            0,
            "router token1 dust"
        );

        // (확인용) 스왑 후 풀 상황
        //_logPoolState(key);
    }

    /// @dev Happy path: token1 -> token0 swap via MiniV4SwapRouter (zeroForOne = false).

    function test_SwapExactInputSingle_OneForZero_Succeeds() public {
        // 1) pool init + add Liquidity
        (PoolKey memory key, uint256 tokenId) = _gienPoolWithWideLiquidity();

        // 2) User - token1 setup
        address user = makeAddr("user");
        vm.startPrank(user);

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token1, user, 1_000e18);
        IERC20(token1).approve(address(router), type(uint256).max);

        uint256 u0Before = IERC20(token0).balanceOf(user);
        uint256 u1Before = IERC20(token1).balanceOf(user);

        // 3) call SwapExactInputSingle through MiniV4SwapRoute
        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: false, // token1 -> token0
                amountIn: uint128(100e18),
                amountOutMin: 0,
                hookData: bytes("")
            });
        uint256 amountOut = router.swapExactInputSingle(params);
        vm.stopPrank();

        // 4) Verification

        // amountOut > 0
        assertGt(amountOut, 0, "amountOut should > 0");

        // token1 : balance = u1Before - amountIn
        // token1 amountIn 만큼 감소
        assertEq(
            u1Before - 100e18,
            IERC20(token1).balanceOf(user),
            "token 1 balance must be equal"
        );

        // token0 : amountOut + u0Before = balance
        assertEq(
            IERC20(token0).balanceOf(user),
            u0Before + amountOut,
            "token 0 balance must be equal"
        );

        // miniRouter : dust
        assertEq(
            IERC20(token0).balanceOf(address(router)),
            0,
            "Dust in miniRouter"
        );
        assertEq(
            IERC20(token1).balanceOf(address(router)),
            0,
            "Dust in miniRouter"
        );

        // logging
        //_logPoolState(key);
    }

    /// ======================= Revert / guard paths =======================

    /// @dev amountIn = 0 should revert (invalid swap request).
    function test_ExactInputSingle_Revert_WhenAmountInZero() public {
        // 1) pool init + add Liquidity
        (PoolKey memory key, uint256 tokenId) = _gienPoolWithWideLiquidity();

        // 2) User setup
        address user = makeAddr("user");
        vm.startPrank(user);

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token1, user, 1_000e18);
        deal(token0, user, 1_000e18);
        IERC20(token1).approve(address(router), type(uint256).max);
        IERC20(token0).approve(address(router), type(uint256).max);

        // 3) call SwapExactInputSingle through MiniV4SwapRoute
        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: 0, // amountIn = 0
                amountOutMin: 0,
                hookData: bytes("")
            });

        // 4) expectRevert
        vm.expectRevert();
        router.swapExactInputSingle(params);
    }

    /// @dev Swap must revert when amountOutMin is unrealistic given pool price (slippage protection).
    function test_ExactInputSingle_Revert_WhenSlippageExceeded() public {
        // 1) pool init + add Liquidity
        (PoolKey memory key, uint256 tokenId) = _gienPoolWithWideLiquidity();

        // 2) User setup
        address user = makeAddr("user");
        vm.startPrank(user);

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        deal(token1, user, 1_000e18);
        deal(token0, user, 1_000e18);
        IERC20(token1).approve(address(router), type(uint256).max);
        IERC20(token0).approve(address(router), type(uint256).max);

        uint256 u0Before = IERC20(token0).balanceOf(user);
        uint256 u1Before = IERC20(token1).balanceOf(user);

        // 3) call SwapExactInputSingle through MiniV4SwapRoute

        uint128 amountIn = 100e18;
        uint128 amountOutMin = 100e18;

        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMin: amountOutMin,
                hookData: bytes("")
            });

        // 4) expectRevert
        vm.expectRevert();
        router.swapExactInputSingle(params);

        // 5) check Balance
        uint256 u0After = IERC20(token0).balanceOf(user);
        uint256 u1After = IERC20(token1).balanceOf(user);
        assertEq(u0Before, u0After, "Transaction must be revert");
        assertEq(u1Before, u1After, "Transaction must be revert");
    }

    /// @dev Revert when swapping against a PoolKey that was never initialized.
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

    /// @dev Revert when pool is initialized but contains zero liquidity.
    function test_ExactInputSingle_Revert_WhenNoLiquidity() public {
        // 1) pool init
        (PoolKey memory key, ) = _initPool();

        // 2) user setup
        address user = makeAddr("user");
        vm.startPrank(user);

        deal(WBTC, user, 1_000e18);
        deal(AAVE, user, 1_000e18);
        IERC20(WBTC).approve(address(router), type(uint256).max);
        IERC20(AAVE).approve(address(router), type(uint256).max);

        // 3) call SwapExactInputSingle through MiniV4SwapRoute

        uint128 amountIn = 100e18;
        uint128 amountOutMin = 1;

        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMin: amountOutMin,
                hookData: bytes("")
            });

        // 4) expectRevert
        vm.expectRevert();
        router.swapExactInputSingle(params);
    }

    /// @dev unlockCallback must only be callable by PoolManager.
    function test_UnlockCallback_Revert_WhenCallerNotPoolManager() public {
        // 1) hacker setup
        address hacker = makeAddr("hacker");
        vm.startPrank(hacker);

        // 2) call unlockCallback
        // 3) expectRevert
        vm.expectRevert("not pool manager");
        router.unlockCallback(bytes("attack"));
    }

    /// ======================= Helpers =======================

    function _deployRouter() internal {
        router = new Miniv4SwapRouter(address(poolManager));
    }

    /// @dev Convenience helper: initialize pool and add generously wide liquidity.
    function _gienPoolWithWideLiquidity()
        internal
        returns (PoolKey memory key, uint256 tokenId)
    {
        (key, ) = _initPool();
        address lp = makeAddr("lp");
        tokenId = _addLiquidityWideDefault(key, lp);
    }

    /// @dev Build default AAVE/WBTC PoolKey (fee 3000, spacing 60, no hooks).
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

    /// @dev Initialize AAVE/WBTC pool at 1:1 price and return PoolKey + initial tick.
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

    /// @dev Mint LP via PositionManager using Permit2 allowances.
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
        // 0) LP에 자금 지급
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);
        deal(t0, provider, uint256(amount0Max));
        deal(t1, provider, uint256(amount1Max));

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

    /// @dev Adds wide-range (almost full-range) liquidity with symmetric 100e18/100e18.

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
            1e18,
            uint128(100e18),
            uint128(100e18),
            provider
        );
    }

    /// @dev Decode packed PositionInfo into (poolId, tickLower, tickUpper, hasSubscriber).
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

    /// @dev Build a canonical PoolKey for (tokenA, tokenB) with given fee/spacing/hooks.
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

    /// @dev 현재 풀 상태 로깅 함수
    // function _logPoolState(PoolKey memory key) internal view {
    //     PoolId id = key.toId();

    //     // getSlot0 시그니처는 v4 버전에 따라 약간 다를 수 있음.
    //     // IPoolManager 인터페이스의 정의를 열어 반환값 개수를 '정확히' 맞춰줘.
    //     // 보통 (sqrtPriceX96, tick, ...) 형태라서 앞의 2개만 받아도 됨.
    //     (uint160 sqrtPriceX96, int24 tick,  /* ... */) = poolManager.getSlot0(
    //         id
    //     );

    //     address token0 = Currency.unwrap(key.currency0);
    //     address token1 = Currency.unwrap(key.currency1);

    //     uint256 bal0 = IERC20(token0).balanceOf(address(poolManager));
    //     uint256 bal1 = IERC20(token1).balanceOf(address(poolManager));

    //     console2.log("---- POOL STATE ----");
    //     console2.log("tickSpacing     :", key.tickSpacing);
    //     console2.log("sqrtPriceX96    :", sqrtPriceX96);
    //     console2.logInt(tick);
    //     console2.log("token0 (pm bal) :", bal0);
    //     console2.log("token1 (pm bal) :", bal1);
    // }
}
