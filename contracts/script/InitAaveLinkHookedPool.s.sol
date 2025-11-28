// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// Uniswap v4 core
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

// Uniswap v4 periphery
import {
    IPositionManager
} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

// ERC20
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title InitAaveLinkHookedPool
/// @notice One–off script to bootstrap an AAVE/LINK Uniswap v4 pool that is
///         wired to your custom hook, and to seed it with a full-range LP
///         position using the deployer’s token balances.
/// @dev
/// Env requirements:
/// - DEPLOYER_PRIVATE_KEY        : EOA that owns the initial LP NFT
/// - POOL_MANAGER                : Uniswap v4 PoolManager
/// - POSITION_MANAGER            : Uniswap v4 PositionManager
/// - PERMIT2                     : Permit2 contract used by PositionManager
/// - AAVE_UNDERLYING_SEPOLIA     : AAVE ERC20 address on Sepolia
/// - LINK_UNDERLYING_SEPOLIA     : LINK ERC20 address on Sepolia
/// - HOOK                        : deployed hook address (e.g. SwapPriceLoggerHook)
///
/// Typical flow:
/// 1) Deploy HookFactory + hook (see other scripts).
/// 2) Initialize the AAVE/LINK pool once (either off-chain or by calling
///    `_initPool` from a separate script).
/// 3) Run this script to:
///    - build the PoolKey for (AAVE, LINK, fee=3000, spacing=10, hooks=HOOK)
///    - approve Permit2 + PositionManager
///    - mint a full-range LP position using *all* AAVE/LINK held by `provider`.

contract InitAaveLinkHookedPool is Script {
    using PoolIdLibrary for PoolKey;

    IPoolManager public poolManager;
    IPositionManager public positionManager;
    IPermit2 public permit2;

    address public AAVE;
    address public LINK;
    IHooks public hook;

    /// @dev Build PoolKey for the AAVE/LINK pair (fee=3000, tickSpacing=10, hooks=hook).
    ///      Token ordering follows Uniswap convention: lower address becomes currency0.
    function _buildAaveLinkPoolKey()
        internal
        view
        returns (PoolKey memory key)
    {
        address token0;
        address token1;

        // Sort token addresses (lower address is currency0).
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

    /// @dev Initialize the hooked AAVE/LINK pool at a 1:1 price.
    /// @notice Not called in `run()` at the moment. Use from a dedicated
    ///         “init-only” script if you still need an on-chain initializer.
    function _initPool() internal returns (PoolKey memory key, int24 initTick) {
        key = _buildAaveLinkPoolKey();

        // 초기가격 1:1
        uint160 sqrtPriceX96 = uint160(1) << 96;

        // init
        initTick = poolManager.initialize(key, sqrtPriceX96);
        console2.log("Initialized tick:", initTick);
        // 1:1 가격이면 tick ~ 0 근처라서 대략 검증
        // 필요 없으면 주석 처리해도 됨
        if (initTick > 10 || initTick < -10) {
            console2.log("WARNING: initTick is far from 0");
        }

        PoolId poolId = key.toId();
        // console2.log("PoolId:", PoolId.unwrap(poolId));
    }

    /// @dev Provide bootstrap liquidity:
    ///      - Mint a full-range position
    ///      - Use the provider's entire AAVE/LINK balances as max amounts
    ///      - Set liquidity ~= min(bal0, bal1) (clamped to uint128)
    function _bootstrapLiquidity(
        PoolKey memory key,
        address provider
    ) internal returns (uint256 tokenId, uint256 spent0, uint256 spent1) {
        address t0 = Currency.unwrap(key.currency0);
        address t1 = Currency.unwrap(key.currency1);

        // provider bal
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        console2.log("PROVIDER :", provider);
        console2.log("TOKEN 0 BALANCE :", t0, bal0Before);
        console2.log("TOKEN 1 BALANCE :", t1, bal1Before);
        require(bal0Before > 0 && bal1Before > 0, "no tokens to provide");

        // Permit2 setup
        IERC20(t0).approve(address(permit2), bal0Before);
        IERC20(t1).approve(address(permit2), bal1Before);

        uint160 max160 = type(uint160).max;
        uint48 neverExpire = type(uint48).max;

        permit2.approve(t0, address(positionManager), max160, neverExpire);
        permit2.approve(t1, address(positionManager), max160, neverExpire);

        // full range
        int24 spacing = key.tickSpacing;
        int24 lower = (TickMath.MIN_TICK / spacing) * spacing;
        int24 upper = (TickMath.MAX_TICK / spacing) * spacing;

        // liquidity / amountMax
        // amountMax = balanceOf(provider), liquidity -  min(bal0, bal1)
        uint128 amount0Max = bal0Before > type(uint128).max
            ? type(uint128).max
            : uint128(bal0Before);
        uint128 amount1Max = bal1Before > type(uint128).max
            ? type(uint128).max
            : uint128(bal1Before);

        uint256 minBal = bal0Before < bal1Before ? bal0Before : bal1Before;
        if (minBal > type(uint128).max) {
            minBal = type(uint128).max;
        }
        uint128 liquidity = uint128(minBal);

        console2.log("Using liquidity:", liquidity);
        console2.log("amount0Max:", amount0Max, "amount1Max:", amount1Max);

        // Actions (MINT_POSITION, SETTLE_PAIR)
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            lower,
            upper,
            liquidity,
            amount0Max,
            amount1Max,
            provider, // LP NFT owner: provider(관리자)
            bytes("") // hookData
        );
        params[1] = abi.encode(key.currency0, key.currency1);
        uint256 beforeId = positionManager.nextTokenId();

        positionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;
    }

    /// @notice Script entrypoint. Assumes the AAVE/LINK pool is already
    ///         initialized and the hook is registered for that pool key.
    function run() external {
        // 1) load env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address provider = vm.addr(deployerPrivateKey);

        address positionManagerAddr = vm.envAddress("POSITION_MANAGER");
        address permit2Addr = vm.envAddress("PERMIT2");
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");

        // Sepolia Token Address (.env)
        AAVE = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        LINK = vm.envAddress("LINK_UNDERLYING_SEPOLIA");
        address hookAddr = vm.envAddress("HOOK");

        poolManager = IPoolManager(poolManagerAddr);
        positionManager = IPositionManager(positionManagerAddr);
        permit2 = IPermit2(permit2Addr);
        hook = IHooks(hookAddr);

        console2.log("Deployer     :", vm.addr(deployerPrivateKey));
        console2.log("PoolManager  :", poolManagerAddr);
        console2.log("AAVE address :", AAVE);
        console2.log("LINK address :", LINK);
        console2.log("Hook address :", hookAddr);

        PoolKey memory key = _buildAaveLinkPoolKey();
        vm.startBroadcast(deployerPrivateKey);

        /// tokenId = 20842
        (uint256 tokenId, uint256 spent0, uint256 spent1) = _bootstrapLiquidity(
            key,
            provider
        );
        vm.stopBroadcast();

        console2.log("=== Liquidity bootstrapped ===");
        console2.log("LP tokenId:", tokenId);
        console2.log("spent token0:", spent0);
        console2.log("spent token1:", spent1);
    }
}
