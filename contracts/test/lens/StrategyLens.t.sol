// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Commons
import {IERC20, IERC20Metadata} from "../../src/interfaces/IERC20.sol";
import {
    IERC721
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

// Forkcast-Defi contracts
import {UserAccount} from "../../src/accounts/UserAccount.sol";
import {AccountFactory} from "../../src/factory/AccountFactory.sol";
import {StrategyRouter} from "../../src/router/StrategyRouter.sol";
import {Miniv4SwapRouter} from "../../src/uniswapV4/Miniv4SwapRouter.sol";
import {StrategyLens} from "../../src/lens/StrategyLens.sol";

// AAVE-V3
import {
    IPoolAddressesProvider
} from "../../src/interfaces/aave-v3/IPoolAddressesProvider.sol";
import {
    IAaveProtocolDataProvider
} from "../../src/interfaces/aave-v3/IAaveProtocolDataProvider.sol";
import {IPool} from "../../src/interfaces/aave-v3/IPool.sol";
import {
    IPriceOracleGetter
} from "../../src/interfaces/aave-v3/IPriceOracleGetter.sol";

// Hook
import {SwapPriceLoggerHook} from "../../src/hook/SwapPriceLoggerHook.sol";
import {HookMiner} from "../../src/libs/HookMiner.sol";
import {Hooks} from "../../src/libs/Hooks.sol";

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

/**
 * @notice Console-only integration probe for the full Forkcast pipeline on Sepolia.
 *
 * Wiring:
 *  - Fork Sepolia Aave V3 + Uniswap v4 (PoolManager, PositionManager, Permit2).
 *  - Deploy StrategyRouter + StrategyLens against real protocol addresses.
 *  - Bootstrap a wide Uniswap v4 pool and a “demo” LP position.
 *
 * Tests:
 *  - Open one leveraged position through StrategyRouter.
 *  - Read everything back via StrategyLens (Aave overview, per-reserve view, v4 LP view).
 *  - Dump results to console for manual inspection / dashboard design.
 *
 * This is intentionally more of a “live playground” than a strict unit test:
 * break-glass debugging and data-shaping for the frontend.
 */
contract StrategyLensConsoleTest is Test {
    using PoolIdLibrary for PoolKey;

    // ------- Core contracts -------
    StrategyRouter public strategyRouter;
    StrategyLens public strategyLens;
    AccountFactory public factory;
    Miniv4SwapRouter public miniRouter;

    // Tokens
    IERC20 public supplyToken; // 예: AAVE
    IERC20 public borrowToken; // 예: LINK

    // AAVE
    IPoolAddressesProvider public aavePoolAddressProvider;
    IAaveProtocolDataProvider public aaveProtocolDataProvider;
    IPool public aavePool;
    IPriceOracleGetter public aaveOracle;

    // Uniswap-V4
    IPoolManager public uniPoolManager;
    IPositionManager public uniPositionManager;
    IPermit2 public permit2;
    PoolKey public poolKey;
    address public poolToken0;
    address public poolToken1;

    // Hook
    SwapPriceLoggerHook public hook;

    // Actors
    address internal admin;

    // ========================= setUp =========================
    /**
     * @dev Full on-chain wiring on a Sepolia fork:
     *  - pull all required protocol addresses from env
     *  - deploy mini swap router, hook, factory, strategy router, lens
     *  - initialize a wide Uniswap v4 pool and bootstrap admin LP
     */
    function setUp() public {
        // 1) Fork Sepolia
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        assertEq(block.chainid, 11155111, "not on sepolia");

        // 2-1) Aave Setup
        address supplyTokenAddr = vm.envAddress("AAVE_UNDERLYING_SEPOLIA");
        address borrowTokenAddr = vm.envAddress("LINK_UNDERLYING_SEPOLIA");
        supplyToken = IERC20(supplyTokenAddr);
        borrowToken = IERC20(borrowTokenAddr);

        address aavePoolAddressProviderAddr = vm.envAddress(
            "AAVE_POOL_ADDRESSES_PROVIDER"
        );
        aavePoolAddressProvider = IPoolAddressesProvider(
            aavePoolAddressProviderAddr
        );

        address aaveProtocolDataProviderAddr = vm.envAddress(
            "AAVE_PROTOCOL_DATA_PROVIDER"
        );
        aaveProtocolDataProvider = IAaveProtocolDataProvider(
            aaveProtocolDataProviderAddr
        );

        aavePool = IPool(aavePoolAddressProvider.getPool());

        // Oracle (env 이름은 네가 쓰는 이름에 맞춰 수정)
        address aaveOracleAddr = vm.envAddress("AAVE_ORACLE");
        aaveOracle = IPriceOracleGetter(aaveOracleAddr);

        // 2-2) Uniswap Setup
        address uniPoolManagerAddr = vm.envAddress("POOL_MANAGER");
        uniPoolManager = IPoolManager(uniPoolManagerAddr);
        address uniPositionMangerAddr = vm.envAddress("POSITION_MANAGER");
        uniPositionManager = IPositionManager(uniPositionMangerAddr);
        address permit2Addr = vm.envAddress("PERMIT2");
        permit2 = IPermit2(permit2Addr);

        miniRouter = new Miniv4SwapRouter(address(uniPoolManager));

        assertGt(
            address(uniPoolManager).code.length,
            0,
            "poolManager not contract"
        );
        assertGt(
            address(uniPositionManager).code.length,
            0,
            "posManager not contract"
        );
        assertGt(address(permit2).code.length, 0, "permit2 not contract");
        assertGt(address(miniRouter).code.length, 0, "miniRouter not deployed");

        // 6) Hook + PoolKey deploy
        (SwapPriceLoggerHook _hook, PoolKey memory key) = _deployHook();
        hook = _hook;
        poolKey = key;

        // 3) admin EOA
        admin = makeAddr("admin");
        vm.startPrank(admin);

        deal(address(supplyToken), admin, 1_000e18);
        deal(address(borrowToken), admin, 1_000e18);

        // 4) factory
        factory = new AccountFactory(aavePoolAddressProviderAddr);
        assertGt(address(factory).code.length, 0, "factory not deployed");

        // 5) router
        strategyRouter = new StrategyRouter(
            address(aavePoolAddressProvider),
            address(factory),
            address(aaveProtocolDataProvider),
            address(miniRouter),
            address(uniPositionManager),
            address(permit2)
        );
        assertGt(
            address(strategyRouter).code.length,
            0,
            "strategyRouter not deployed"
        );

        strategyRouter.initPermit2(
            address(supplyToken),
            address(borrowToken),
            address(uniPoolManager)
        );

        // 7) Pool init
        uint160 sqrtPriceX96 = uint160(1) << 96; // 1:1
        int24 initTick = _initPool(key, sqrtPriceX96);

        // 8) Router pool config
        int24 spacing = key.tickSpacing;
        int24 lower = (TickMath.MIN_TICK / spacing) * spacing;
        int24 upper = (TickMath.MAX_TICK / spacing) * spacing;

        strategyRouter.setUniswapV4PoolConfig(key, lower, upper);

        (
            address token0,
            address token1,
            uint24 fee,
            int24 tickSpacing,
            int24 defaultTickLower,
            int24 defaultTickUpper
        ) = strategyRouter.getUniswapV4PoolConfig();

        poolToken0 = token0;
        poolToken1 = token1;

        assertEq(lower, defaultTickLower);
        assertEq(upper, defaultTickUpper);
        assertEq(Currency.unwrap(key.currency0), token0);
        assertEq(Currency.unwrap(key.currency1), token1);
        assertEq(spacing, tickSpacing);

        // 9) Admin bootstrap LP
        uint256 bal0Admin = IERC20(supplyToken).balanceOf(admin);
        uint256 bal1Admin = IERC20(borrowToken).balanceOf(admin);

        uint128 liquidity = strategyRouter.previewLiquidity(
            bal0Admin,
            bal1Admin
        );
        assertGt(liquidity, 0, "preview liquidity must be > 0");

        uint128 amount0Max = uint128(bal0Admin);
        uint128 amount1Max = uint128(bal1Admin);
        require(uint256(amount0Max) == bal0Admin, "bal0 overflow");
        require(uint256(amount1Max) == bal1Admin, "bal1 overflow");

        (uint256 tokenId, uint256 spent0, uint256 spent1) = _addLiquidity(
            key,
            admin,
            lower,
            upper,
            liquidity,
            amount0Max,
            amount1Max,
            admin
        );

        uint128 afterLiquidity = uniPositionManager.getPositionLiquidity(
            tokenId
        );

        vm.stopPrank();

        // 10) Lens deploy
        strategyLens = new StrategyLens(
            admin,
            address(aavePoolAddressProvider),
            address(aavePool),
            address(aaveProtocolDataProvider),
            address(factory),
            address(aaveOracle),
            address(uniPoolManager),
            address(uniPositionManager),
            address(strategyRouter)
        );
        assertGt(address(strategyLens).code.length, 0, "lens not deployed");
    }

    // ========================= Lens console tests =========================

    /// @dev Open a position and dump:
    ///      - high-level Aave account overview
    ///      - first few reserve static configs
    function test_Lens_UserAaveOverview_And_AllReserves() public {
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (address vault, , , , ) = _openPositionFor(user, supplyAmount);

        StrategyLens.UserAaveOverview memory ov = strategyLens
            .getUserAaveOverview(user);

        console2.log("=== UserAaveOverview ===");
        console2.log("user          :", ov.user);
        console2.log("vault         :", ov.vault);
        console2.log("collateralBase:", ov.totalCollateralBase);
        console2.log("debtBase      :", ov.totalDebtBase);
        console2.log("availableBase :", ov.availableBorrowBase);
        console2.log("ltv           :", ov.ltv);
        console2.log("liqThreshold  :", ov.currentLiquidationThreshold);
        console2.log("healthFactor  :", ov.healthFactor);

        assertEq(ov.vault, vault);
        assertGt(ov.totalCollateralBase, 0);
        assertGt(ov.totalDebtBase, 0);

        StrategyLens.ReserveStaticData[] memory reserves = strategyLens
            .getAllAaveReserves();

        console2.log("=== All Aave Reserves (first few) ===");
        console2.log("reserves length:", reserves.length);

        uint256 maxPrint = reserves.length < 5 ? reserves.length : 5;
        for (uint256 i; i < maxPrint; ++i) {
            console2.log("-- idx", i, " --");
            console2.log("asset   :", reserves[i].asset);
            console2.log("symbol  :", reserves[i].symbol);
            console2.log("ltv     :", reserves[i].ltv);
            console2.log("liqThr  :", reserves[i].liquidationThreshold);
            console2.log("borrowCap:", reserves[i].borrowCap);
            console2.log("supplyCap:", reserves[i].supplyCap);
            console2.log("paused  :", reserves[i].paused);
        }
    }

    /// @dev Open a position and inspect:
    ///      - per-reserve balances (aToken / stable / variable debt)
    ///      - corresponding Uni v4 LP snapshot
    function test_Lens_UserReservePositions_And_UniPosition() public {
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (, uint256 tokenId, , , ) = _openPositionFor(user, supplyAmount);

        // Aave per-asset positions
        address[] memory assets = new address[](2);
        assets[0] = address(supplyToken);
        assets[1] = address(borrowToken);

        StrategyLens.UserReservePosition[] memory positions = strategyLens
            .getUserReservePositions(user, assets);

        console2.log("=== UserReservePositions ===");
        for (uint256 i; i < positions.length; ++i) {
            StrategyLens.UserReservePosition memory p = positions[i];

            console2.log("-- idx", i, " --");
            console2.log("asset        :", p.asset);
            console2.log("aTokenBal    :", p.aTokenBalance);
            console2.log("stableDebt   :", p.stableDebt);
            console2.log("variableDebt :", p.variableDebt);
        }

        // Uni v4 position
        StrategyLens.UniPositionOverview memory uniView = strategyLens
            .getUserUniPosition(user, tokenId);

        console2.log("=== UniPositionOverview ===");
        console2.log("token0      :", uniView.token0);
        console2.log("token1      :", uniView.token1);
        console2.log("liquidity   :", uniView.liquidity);
        console2.log("amount0Now  :", uniView.amount0Now);
        console2.log("amount1Now  :", uniView.amount1Now);
        console2.log("tickLower   :", uniView.tickLower);
        console2.log("tickUpper   :", uniView.tickUpper);
        console2.log("currentTick :", uniView.currentTick);
        console2.log("sqrtPriceX96:", uniView.sqrtPriceX96);

        assertGt(uniView.liquidity, 0, "uni liquidity must be > 0");
    }

    /// @dev End-to-end “strategy position” snapshot:
    ///      single call that stitches core metadata + Uni v4 + Aave account view.
    function test_Lens_StrategyPositionView_Console() public {
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (address vault, uint256 tokenId, , , ) = _openPositionFor(
            user,
            supplyAmount
        );

        StrategyLens.StrategyPositionView memory v = strategyLens
            .getStrategyPositionView(tokenId);

        console2.log("=== StrategyPositionView ===");
        console2.log("-- core --");
        console2.log("owner       :", v.core.owner);
        console2.log("vault       :", v.core.vault);
        console2.log("supplyAsset :", v.core.supplyAsset);
        console2.log("borrowAsset :", v.core.borrowAsset);
        console2.log("isOpen      :", v.core.isOpen);

        console2.log("-- Uni v4 --");
        console2.log("uniToken0   :", v.uniToken0);
        console2.log("uniToken1   :", v.uniToken1);
        console2.log("liquidity   :", v.liquidity);
        console2.log("amount0Now  :", v.amount0Now);
        console2.log("amount1Now  :", v.amount1Now);
        console2.log("tickLower   :", v.tickLower);
        console2.log("tickUpper   :", v.tickUpper);
        console2.log("currentTick :", v.currentTick);
        console2.log("sqrtPriceX96:", v.sqrtPriceX96);

        console2.log("-- Aave (vault) --");
        console2.log("totalCollateralBase:", v.totalCollateralBase);
        console2.log("totalDebtBase      :", v.totalDebtBase);
        console2.log("availableBorrowBase:", v.availableBorrowBase);
        console2.log("ltv                :", v.ltv);
        console2.log("liqThreshold       :", v.currentLiquidationThreshold);
        console2.log("healthFactor       :", v.healthFactor);

        // 최소한의 sanity check
        assertEq(v.core.owner, user);
        assertEq(v.core.vault, vault);
        assertTrue(v.core.isOpen, "position must be open");
        assertGt(v.totalDebtBase, 0);
        assertGt(v.liquidity, 0);
    }

    /// @dev Dump all reserve rate data (liquidity + borrow rates) for quick sanity checks.

    function test_Lens_AllReserveRates_Console() public {
        StrategyLens.ReserveRateData[] memory rates = strategyLens
            .getAllReserveRates();

        console2.log("=== AllReserveRates ===");
        console2.log("len:", rates.length);

        for (uint256 i = 0; i < rates.length; ++i) {
            console2.log("-- idx", i, "--");
            console2.log("asset :", rates[i].asset);
            console2.log("symbol:", rates[i].symbol);
            console2.log("liqRateRay      :", rates[i].liquidityRateRay);
            console2.log("varBorrowRateRay:", rates[i].variableBorrowRateRay);
            console2.log("stbBorrowRateRay:", rates[i].stableBorrowRateRay);
        }

        // 최소 검증
        assertGt(rates.length, 0, "no reserves");
    }

    // ========================= Helper functions =========================

    /// @dev Use HookMiner to find a valid salt for AFTER_SWAP hook, then deploy
    ///      SwapPriceLoggerHook and build a PoolKey wired to that hook.
    function _deployHook()
        internal
        returns (SwapPriceLoggerHook _hook, PoolKey memory key)
    {
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        bytes memory constructorArgs = abi.encode(address(uniPoolManager));

        (address expectedHookAddr, bytes32 salt) = HookMiner.find({
            deployer: address(this),
            flags: uint160(Hooks.AFTER_SWAP_FLAG),
            creationCode: creationCode,
            constructorArgs: constructorArgs
        });

        _hook = new SwapPriceLoggerHook{salt: salt}(address(uniPoolManager));

        assertEq(address(_hook), expectedHookAddr, "hook address mismatch");

        uint24 fee = 3000;
        int24 tickSpacing = 10;

        key = _buildPoolKey(
            address(supplyToken),
            address(borrowToken),
            fee,
            tickSpacing,
            IHooks(address(_hook))
        );
    }

    /// @dev Helper that:
    ///      - creates a new vault for `user`
    ///      - opens a leveraged position via StrategyRouter
    ///      - returns vault address, new LP tokenId and basic Aave account data
    function _openPositionFor(
        address user,
        uint256 supplyAmount
    )
        internal
        returns (
            address vault,
            uint256 newTokenId,
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 healthFactor
        )
    {
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        uint256 nextIdBefore = uniPositionManager.nextTokenId();

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);
        strategyRouter.openPosition(
            address(supplyToken),
            supplyAmount,
            address(borrowToken),
            0 // targetHF1e18
        );
        vm.stopPrank();

        // vault 생성
        vault = factory.accountOf(user);
        assertTrue(vault != address(0), "vault should exist after open");

        // Aave 계정 상태
        (totalCollateralBase, totalDebtBase, , , , healthFactor) = aavePool
            .getUserAccountData(vault);

        assertGt(totalCollateralBase, 0);
        assertGt(totalDebtBase, 0);
        assertGt(healthFactor, 0);

        // 새 LP tokenId
        uint256 nextIdAfter = uniPositionManager.nextTokenId();
        assertEq(
            nextIdAfter,
            nextIdBefore + 1,
            "one new LP NFT should be minted"
        );
        newTokenId = nextIdAfter - 1;

        uint128 liq = uniPositionManager.getPositionLiquidity(newTokenId);
        assertGt(liq, 0, "LP liquidity must be > 0");
    }

    /// @dev Build a canonical PoolKey for the (token0, token1, fee, spacing, hooks) pair.
    function _buildPoolKey(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        IHooks hooks
    ) internal pure returns (PoolKey memory key) {
        address token0;
        address token1;

        if (_token0 < _token1) {
            token0 = _token0;
            token1 = _token1;
        } else {
            token0 = _token1;
            token1 = _token0;
        }

        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);

        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: _fee,
            tickSpacing: _tickSpacing,
            hooks: hooks
        });
    }

    /// @dev Initialize the v4 pool on the PoolManager.
    function _initPool(
        PoolKey memory key,
        uint160 sqrtPriceX96
    ) internal returns (int24 initTick) {
        initTick = uniPoolManager.initialize(key, sqrtPriceX96);
    }

    /// @dev Add liquidity through PositionManager using Permit2-based allowances.
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

        // Permit2 approve
        IERC20(t0).approve(address(permit2), type(uint256).max);
        IERC20(t1).approve(address(permit2), type(uint256).max);
        uint160 max160 = type(uint160).max;
        uint48 neverExpire = type(uint48).max;
        permit2.approve(t0, address(uniPositionManager), max160, neverExpire);
        permit2.approve(t1, address(uniPositionManager), max160, neverExpire);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

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

        uint256 beforeId = uniPositionManager.nextTokenId();
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        uniPositionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        uint256 afterId = uniPositionManager.nextTokenId();
        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;

        assertEq(afterId, beforeId + 1, "one bootstrap LP NFT minted");
    }
}
