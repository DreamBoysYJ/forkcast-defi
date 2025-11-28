// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Commons
import {IERC20} from "../../src/interfaces/IERC20.sol";

// Forkcast-Defi contracts
import {Miniv4SwapRouter} from "../../src/uniswapV4/Miniv4SwapRouter.sol";

// Uniswap-V4
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {
    IPositionManager
} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

// Hook
import {SwapPriceLoggerHook} from "../../src/hook/SwapPriceLoggerHook.sol";
import {Hooks} from "../../src/libs/Hooks.sol";
import {HookMiner} from "../../src/libs/HookMiner.sol";

/**
 * @title SwapPriceLoggerHookTest
 * @notice End-to-end tests for SwapPriceLoggerHook integrated with Uniswap v4 and MiniV4SwapRouter.
 *         Scope:
 *           - Deploy hook via HookMiner (CREATE2, AFTER_SWAP only)
 *           - Initialize a pool, seed liquidity, and route swaps through MiniV4SwapRouter
 *           - Assert that afterSwap emits SwapPriceLogged with the correct poolId
 *           - Provide a debug helper to inspect raw logs when needed
 */
contract SwapPriceLoggerHookTest is Test {
    using PoolIdLibrary for PoolKey;

    // Uniswap-V4
    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IPermit2 public permit2;
    Miniv4SwapRouter public miniRouter;
    SwapPriceLoggerHook public hook;

    address public token0; // AAVE
    address public token1; // LINK
    PoolKey public poolKey;

    address internal admin;

    event SwapPriceLogged(
        PoolId indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint256 timestamp
    );

    function setUp() public {
        // 1) Fork Sepolia
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        assertEq(block.chainid, 11155111, "not on sepolia");

        // 2) Choose underlying tokens (AAVE / LINK)
        address token0Addr = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        address token1Addr = vm.envAddress("LINK_UNDERLYING_SEPOLIA");
        token0 = token0Addr;
        token1 = token1Addr;

        // 3) Wire up Uniswap v4 core/periphery + Permit2
        address pm = vm.envAddress("POOL_MANAGER");
        address posm = vm.envAddress("POSITION_MANAGER");
        address permit2Addr = vm.envAddress("PERMIT2");

        poolManager = IPoolManager(pm);
        positionManager = IPositionManager(posm);
        permit2 = IPermit2(permit2Addr);

        // 4) Deploy minimal swap router used as the entrypoint for swaps
        miniRouter = new Miniv4SwapRouter(address(poolManager));
        assertGt(address(miniRouter).code.length, 0, "miniRouter not deployed");

        // 5) Deploy hook via HookMiner and build PoolKey with AFTER_SWAP flag
        (SwapPriceLoggerHook _hook, PoolKey memory key) = _deployHook();
        hook = _hook;
        poolKey = key;

        // 6) admin
        admin = makeAddr("admin");
        vm.startPrank(admin);

        deal(token0, admin, 1_000e18);
        deal(token1, admin, 1_000e18);

        // 7) Initialize the pool at 1:1 price
        uint160 sqrtPriceX96 = uint160(1) << 96;
        int24 initTick = _initPool(key, sqrtPriceX96);
        console2.log("initTick :", initTick);

        // 8) Configure full-range ticks for bootstrap liquidity
        int24 spacing = key.tickSpacing;
        int24 lower = (TickMath.MIN_TICK / spacing) * spacing;
        int24 upper = (TickMath.MAX_TICK / spacing) * spacing;

        // 9) Add bootstrap liquidity using Permit2
        uint256 bal0Admin = IERC20(token0).balanceOf(admin);
        uint256 bal1Admin = IERC20(token1).balanceOf(admin);

        uint128 amount0Max = uint128(bal0Admin);
        uint128 amount1Max = uint128(bal1Admin);
        require(uint256(amount0Max) == bal0Admin, "bal0 overflow");
        require(uint256(amount1Max) == bal1Admin, "bal1 overflow");

        uint128 liquidity = uint128(1_000e18);

        (uint256 lpTokenId, uint256 spent0, uint256 spent1) = _addLiquidity(
            key,
            admin,
            lower,
            upper,
            liquidity,
            amount0Max,
            amount1Max,
            admin
        );

        console2.log("bootstrap LP tokenId", lpTokenId);
        console2.log("spent0", spent0);
        console2.log("spent1", spent1);

        vm.stopPrank();
    }

    // ============================ Success cases ============================

    /// @dev Swap through MiniV4SwapRouter and assert that the hook emits SwapPriceLogged.
    function test_Swap_Emits_SwapPriceLogged() public {
        address trader = makeAddr("trader");
        uint256 amountIn = 10e18;
        deal(token0, trader, amountIn);

        vm.startPrank(trader);
        IERC20(token0).approve(address(miniRouter), amountIn);

        PoolId poolId = poolKey.toId();

        // Only care that the hook fires for the correct poolId and event signature;
        // tick / price / timestamp are not asserted here.
        vm.expectEmit(true, true, false, false, address(hook));
        emit SwapPriceLogged(poolId, 0, 0, 0);

        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: Currency.unwrap(poolKey.currency0) == token0,
                amountIn: uint128(amountIn),
                amountOutMin: 0,
                hookData: bytes("")
            });

        miniRouter.swapExactInputSingle(params);
        vm.stopPrank();
    }

    // ============================ Debug helper ============================

    /// @dev Same swap as above, but records and prints all logs for manual inspection.
    function test_Swap_Emits_SwapPriceLogged_Debug() public {
        address trader = makeAddr("trader");
        uint256 amountIn = 1e18;
        deal(token0, trader, amountIn);

        vm.startPrank(trader);
        IERC20(token0).approve(address(miniRouter), amountIn);

        // --- 로그 기록 시작 ---
        vm.recordLogs();

        Miniv4SwapRouter.ExactInputSingleParams memory params = Miniv4SwapRouter
            .ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: Currency.unwrap(poolKey.currency0) == token0,
                amountIn: uint128(amountIn),
                amountOutMin: 0,
                hookData: bytes("")
            });

        miniRouter.swapExactInputSingle(params);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        console2.log("=== total logs ===", logs.length);

        for (uint256 i; i < logs.length; ++i) {
            console2.log("LOG #", i);
            console2.log(" emitter:", logs[i].emitter);
            console2.logBytes32(logs[i].topics[0]); // 이벤트 시그니처

            if (logs[i].topics.length > 1) {
                console2.log(" topic1:");
                console2.logBytes32(logs[i].topics[1]);
            }
        }
    }

    // ============================ Hook / pool setup ============================

    /// @dev Use HookMiner to find a valid AFTER_SWAP-only hook salt, deploy via CREATE2,
    ///      and build a PoolKey that references the deployed hook.
    function _deployHook()
        internal
        returns (SwapPriceLoggerHook _hook, PoolKey memory key)
    {
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        bytes memory constructorArgs = abi.encode(address(poolManager));

        (address expectedHookAddr, bytes32 salt) = HookMiner.find({
            deployer: address(this),
            flags: uint160(Hooks.AFTER_SWAP_FLAG),
            creationCode: creationCode,
            constructorArgs: constructorArgs
        });

        _hook = new SwapPriceLoggerHook{salt: salt}(address(poolManager));

        console2.log("EXPECTED HOOK :::", expectedHookAddr);
        console2.log("HOOK DEPLOYED :::", address(_hook));

        assertEq(address(_hook), expectedHookAddr, "hook address mismatch");

        uint24 fee = 3000;
        int24 tickSpacing = 10;

        key = _buildPoolKey(
            token0,
            token1,
            fee,
            tickSpacing,
            IHooks(address(_hook))
        );
    }

    /// @dev Build canonical PoolKey for the chosen token pair.
    function _buildPoolKey(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        IHooks hooks
    ) internal pure returns (PoolKey memory key) {
        address t0;
        address t1;

        if (_token0 < _token1) {
            t0 = _token0;
            t1 = _token1;
        } else {
            t0 = _token1;
            t1 = _token0;
        }

        Currency currency0 = Currency.wrap(t0);
        Currency currency1 = Currency.wrap(t1);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: _fee,
            tickSpacing: _tickSpacing,
            hooks: hooks
        });
    }

    /// @dev Initialize a pool and return the initial tick for sanity checks.
    function _initPool(
        PoolKey memory key,
        uint160 sqrtPriceX96
    ) internal returns (int24 initTick) {
        initTick = poolManager.initialize(key, sqrtPriceX96);
        console2.log("Initialized Tick : ", initTick);
    }

    /// @dev Add liquidity via PositionManager using Permit2 as allowance manager.
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

        // 1) Permit2 approve
        IERC20(t0).approve(address(permit2), type(uint256).max);
        IERC20(t1).approve(address(permit2), type(uint256).max);
        uint160 max160 = type(uint160).max;
        uint48 neverExpire = type(uint48).max;
        permit2.approve(t0, address(positionManager), max160, neverExpire);
        permit2.approve(t1, address(positionManager), max160, neverExpire);

        // 2) Actions (MINT_POSITION, SETTLE_PAIR)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // 3) params
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

        // 4) positionManager -> modifyLiquidities

        uint256 beforeId = positionManager.nextTokenId();
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        // 5) Verification
        uint256 afterId = positionManager.nextTokenId();
        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;

        // silence unused warning
        afterId;
    }
}
