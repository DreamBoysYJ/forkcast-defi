// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Commons
import {IERC20, IERC20Metadata} from "../src/interfaces/IERC20.sol";
import {
    IERC721
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

// Forkcast-Defi contracts
import {UserAccount} from "../src/accounts/UserAccount.sol";
import {AccountFactory} from "../src/factory/AccountFactory.sol";
import {StrategyRouter} from "../src/router/StrategyRouter.sol";
import {AaveModule} from "../src/router/AaveModule.sol";

import {Miniv4SwapRouter} from "../src/uniswapV4/Miniv4SwapRouter.sol";

// AAVE-V3
import {
    IPoolAddressesProvider
} from "../src/interfaces/aave-v3/IPoolAddressesProvider.sol";
import {
    IAaveProtocolDataProvider
} from "../src/interfaces/aave-v3/IAaveProtocolDataProvider.sol";
import {IPool} from "../src/interfaces/aave-v3/IPool.sol";

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
import {SwapPriceLoggerHook} from "../src/hook/SwapPriceLoggerHook.sol";
import {HookMiner} from "../src/libs/HookMiner.sol"; // 네 경로에 맞게
import {Hooks} from "../src/libs/Hooks.sol"; // 네가 복붙한 경로에 맞게

contract StrategyRouterClosePosition is Test {
    StrategyRouter public strategyRouter;
    AccountFactory public factory;
    Miniv4SwapRouter public miniRouter;

    IERC20 public supplyToken; // AAVE
    IERC20 public borrowToken; // LINK

    // AAVE-V3
    IPoolAddressesProvider public aavePoolAddressProvider;
    IAaveProtocolDataProvider public aaveProtocolDataProvider;

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

    event SwapPriceLogged(
        PoolId indexed poolId,
        int24 tick,
        uint160 sqrtPriceX96,
        uint256 timestamp
    );

    event PositionClosed(
        address indexed user,
        address indexed vault,
        uint256 indexed tokenId,
        address supplyAsset,
        address borrowAsset,
        uint256 amountSupplyReturned, // 유저가 최종 받는 A 수량
        uint256 amountBorrowReturned // 유저가 최종 받는 B 수량
    );

    event PositionOpened(
        address indexed user,
        address indexed vault,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 borrowedAmount,
        uint256 tokenId,
        uint256 amount0ForLp,
        uint256 amount1ForLp,
        uint256 spent0,
        uint256 spent1
    );

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

        // 2-2) Uniswap Setup
        address uniPoolManagerAddr = vm.envAddress("POOL_MANAGER");
        uniPoolManager = IPoolManager(uniPoolManagerAddr);
        address uniPositionMangerAddr = vm.envAddress("POSITION_MANAGER");
        uniPositionManager = IPositionManager(uniPositionMangerAddr);
        address permit2Addr = vm.envAddress("PERMIT2");
        permit2 = IPermit2(permit2Addr);

        miniRouter = new Miniv4SwapRouter(address(uniPoolManager)); // Deploy MiniV4SwapRouter

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

        // 훅 + 풀키
        // 5) 훅 + 풀키 세팅
        (SwapPriceLoggerHook _hook, PoolKey memory key) = _deployHook();
        hook = _hook;
        poolKey = key;

        // 3) admin EOA + startPrank
        admin = makeAddr("admin");
        vm.startPrank(admin);

        deal(address(supplyToken), admin, 1_000e18);
        deal(address(borrowToken), admin, 1_000e18);

        // 4) Deploy AccountFactory

        factory = new AccountFactory(aavePoolAddressProviderAddr);
        assertGt(address(factory).code.length, 0, "factory not deployed");

        // 5) Deploy StrategyRouter
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
        address vault = factory.accountOf(address(this));
        assertEq(vault, address(0), "vault should not exist yet");

        strategyRouter.initPermit2(
            address(supplyToken),
            address(borrowToken),
            address(uniPoolManager)
        );

        // 6) Create PoolKey -> Pool Init (fee = 3000 / tickSpacing = 60 / hooks X / 초기 가격 1:1)

        // uint24 _fee = 3000;
        // int24 _tickSpacing = 10;
        // IHooks hooks = IHooks(address(0));

        // PoolKey memory key = _buildPoolKey(
        //     address(supplyToken),
        //     address(borrowToken),
        //     _fee,
        //     _tickSpacing,
        //     hooks
        // );

        // poolKey = key;

        uint160 sqrtPriceX96 = uint160(1) << 96;

        int24 initTick = _initPool(key, sqrtPriceX96);
        console2.log("initTick", initTick);

        // 7) 틱 범위 세팅 (풀 범위)
        int24 spacing = key.tickSpacing;
        int24 lower = (TickMath.MIN_TICK / spacing) * spacing;
        int24 upper = (TickMath.MAX_TICK / spacing) * spacing;

        // 8) Router Config 세팅 (key, tickLower, tickUpper, Id 변수 저장)
        strategyRouter.setUniswapV4PoolConfig(key, lower, upper);

        // 세팅 확인
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
        // if (routerBal == 0 && borrowAmountOut == 0) {
        //     // LP에서 아무것도 못 받았고, 라우터에 남은 borrowAsset도 하나도 없음
        //     revert ZeroBorrowAfterSafety();
        // }

        assertEq(
            lower,
            defaultTickLower,
            "tickLower must be same as admin sets"
        );
        assertEq(
            upper,
            defaultTickUpper,
            "tickLower must be same as admin sets"
        );
        assertEq(
            Currency.unwrap(key.currency0),
            token0,
            "token0 must be same as admin sets"
        );
        assertEq(
            Currency.unwrap(key.currency1),
            token1,
            "token0 must be same as admin sets"
        );
        assertEq(
            spacing,
            tickSpacing,
            "tickSpacing must be same as admin sets"
        );

        // 9) admin -> Add Liquidity (사람들이 스왑을 많이 해도 토큰 비율에 큰 영향이 안 갈정도로 크게 / 범위 최대한 넓게)

        // 최대 liquidity 계산
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
        console2.log("bootstrap LP tokenId", tokenId);
        console2.log("spent0", spent0);
        console2.log("spent1", spent1);

        assertGt(tokenId, 0, "tokenId must be > 0");
        assertTrue(spent0 > 0 || spent1 > 0, "no token spent for liquidity");

        uint128 afterLiquidity = uniPositionManager.getPositionLiquidity(
            tokenId
        );
        assertEq(
            afterLiquidity,
            liquidity,
            "liquidity must be same as increasement"
        );
        console2.log("LIQUIDITY IN POOL :", afterLiquidity);

        vm.stopPrank(); //
    }

    function test_setUp() public pure {
        console2.log("HI");
    }

    /// -------< Succeess Cases >--------------

    /// @dev openPosition  호출 성공
    function test_OpenPosition_HappyPath() public {
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (
            address vault,
            uint256 tokenId,
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 healthFactor
        ) = _openPositionFor(user, supplyAmount);
    }

    /// @dev openPosition -> (trader swap) ->  closePosition 호출 성공
    function test_ClosePosition_HappyPath() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset 부족분 보유
        deal(address(borrowToken), user, 1000e18);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // sanity check
        assertGt(
            collateralBefore,
            0,
            "vault must have collateral before close"
        );
        assertGt(debtBefore, 0, "vault must have debt before close");
        assertGt(hfBefore, 0, "HF must be > 0 before close");

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);
        console2.log("MIN_EXTRA NEEDED ::: ", minExtraFromUser);
        console2.log("MAX_EXTRA NEEDED ::: ", maxExtraFromUser);

        // satity check :
        assertGt(totalDebtToken, 0, "preview: debt must be > 0");
        assertLe(minExtraFromUser, maxExtraFromUser);
        assertLe(maxExtraFromUser, totalDebtToken);

        // 부족분 상한 만큼 미리 approve
        // 유저가 부족분 상한(maxExtraFromUser)만큼 미리 approve
        vm.startPrank(user);
        IERC20(address(borrowToken)).approve(
            address(strategyRouter),
            maxExtraFromUser
        );
        vm.stopPrank();

        // 4) User closePosition
        vm.startPrank(user);

        PoolId poolId = poolKey.toId();
        vm.expectEmit(true, true, false, false, address(hook));
        emit SwapPriceLogged(poolId, 0, 0, 0);

        vm.expectEmit(true, true, true, false, address(strategyRouter));
        emit PositionClosed(
            user,
            vault,
            tokenId,
            address(supplyToken),
            address(borrowToken),
            /* collateralOut     */ 0,
            /* leftoverBorrow    */ 0
        );

        strategyRouter.closePosition(tokenId);
        vm.stopPrank();

        // 4) Verify Aave / Uniswap / User Balance

        // 4-1) Aave 포지션 확인 (담보, 부채 0)
        IPool pool = IPool(aavePoolAddressProvider.getPool());
        (
            uint256 collateralAfter,
            uint256 debtAfter,
            ,
            ,
            ,
            uint256 hfAfter
        ) = pool.getUserAccountData(vault);

        // 진짜 깨끗이 닫혔는지 확인 (필요하면 <= 1 같은 여유도 가능)
        assertEq(debtAfter, 0, "debt must be fully repaid after close");
        assertEq(
            collateralAfter,
            0,
            "collateral must be fully withdrawn after close"
        );
        // HF는 의미 없지만, 부채 0이면 보통 아주 큰 값이거나 0 근처
        console2.log("HF after close:", hfAfter);

        // 4-2) Uniswap v4 LP 포지션 유동성 제거 확인
        uint128 liqAfter = uniPositionManager.getPositionLiquidity(tokenId);
        assertEq(liqAfter, 0, "LP liquidity must be 0 after close");

        // 4-3) 유저가 토큰을 돌려받았는지 확인 (A는 원금, B는 수수료/가격이득)
        uint256 userSupplyAfter = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowAfter = IERC20(address(borrowToken)).balanceOf(user);

        // openPosition 후엔 거의 0에 가까웠을 테니, 닫은 후엔 증가해야 정상
        assertGt(
            userSupplyAfter,
            userSupplyBefore,
            "user must receive back supplyAsset on close"
        );
        console2.log(
            "USER SUPPLY PLUS :::",
            userSupplyAfter - userSupplyBefore
        );

        // 4-4) 같은 포지션을 다시 닫으려 하면 실패해야 함 (isOpen=false)
        vm.startPrank(user);
        vm.expectRevert(StrategyRouter.PositionNotOpen.selector);
        strategyRouter.closePosition(tokenId);
        vm.stopPrank();
    }

    /// @dev openPosition -> (trader swap) ->  collectFee 호출 성공
    function test_CollectFees_HappyPath() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // sanity check
        assertGt(
            collateralBefore,
            0,
            "vault must have collateral before close"
        );
        assertGt(debtBefore, 0, "vault must have debt before close");
        assertGt(hfBefore, 0, "HF must be > 0 before close");
        // 2) 현재 LP 유동성 스냅샷
        uint128 liqBefore = uniPositionManager.getPositionLiquidity(tokenId);
        assertGt(liqBefore, 0, "liquidity must be > 0 before collect");

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 20);

        // 3) Collect 전 후 잔고 비교용
        (address token0, address token1, , , , ) = strategyRouter
            .getUniswapV4PoolConfig();

        uint256 userToken0Before = IERC20(token0).balanceOf(user);
        uint256 userToken1Before = IERC20(token1).balanceOf(user);

        // 4) 유저가 직접 collectFees 호출
        vm.startPrank(user);
        (uint256 collected0, uint256 collected1) = strategyRouter.collectFees(
            tokenId
        );

        console2.log("Collected 0 :::", collected0);
        console2.log("Collected 1 :::", collected1);

        // 5) 수수료 확인     // 6) 정말 수수료가 들어왔는지 확인
        // 최소 한 쪽 토큰이라도 수수료가 > 0 이어야 한다.
        assertGt(collected0 + collected1, 0, "must collect some fees");

        uint256 userToken0After = IERC20(token0).balanceOf(user);
        uint256 userToken1After = IERC20(token1).balanceOf(user);

        // 수수료 = 잔고 증가량과 일치해야 함
        assertEq(
            userToken0After - userToken0Before,
            collected0,
            "user token0 delta must equal collected0"
        );
        assertEq(
            userToken1After - userToken1Before,
            collected1,
            "user token1 delta must equal collected1"
        );

        // 7) collect는 "수수료만" 빼가고, LP 유동성 자체는 그대로여야 함
        uint128 liqAfter = uniPositionManager.getPositionLiquidity(tokenId);
        assertEq(
            liqAfter,
            liqBefore,
            "liquidity must not change after fee collect"
        );

        // 8) 추가로, 바로 한 번 더 collect 하면 거의 0 근처여야 정상 (새로운 스왑 없이)
        vm.startPrank(user);
        (uint256 c0Second, uint256 c1Second) = strategyRouter.collectFees(
            tokenId
        );
        vm.stopPrank();

        // 아주 미세한 라운딩을 고려하려면 == 대신 <= 사용해도 됨
        assertEq(
            c0Second + c1Second,
            0,
            "second collect without new swaps should be zero"
        );
    }

    /// @dev openPosition -> (trader swap) ->  previewClosePosition
    function test_PreviewClosePosition_HappyPath() public {
        // 1) openPosition 으로 레버리지 LP 포지션 오픈
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // sanity check
        assertGt(collateralBefore, 0, "vault must have collateral");
        assertGt(debtBefore, 0, "vault must have debt");
        assertGt(hfBefore, 0, "HF must be > 0 before close");

        // 2) 트레이더 스왑으로 LP에 수수료 쌓이게 만들기
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) previewClosePosition 호출
        (
            address vaultOut,
            address supplyAssetOut,
            address borrowAssetOut,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            uint256 amount0FromLp,
            uint256 amount1FromLp
        ) = strategyRouter.previewClosePosition(tokenId);

        // ---------- 검증 (assert) ----------

        // (1) 메타데이터 일치
        assertEq(vaultOut, vault, "preview: vault mismatch");
        assertEq(
            supplyAssetOut,
            address(supplyToken),
            "preview: wrong supplyAsset"
        );
        assertEq(
            borrowAssetOut,
            address(borrowToken),
            "preview: wrong borrowAsset"
        );

        // (2) 빚과 관계 값들이 말이 되는지
        assertGt(totalDebtToken, 0, "preview: debt must be > 0");

        // min ≤ max ≤ totalDebt
        assertLe(minExtraFromUser, maxExtraFromUser);
        assertLe(maxExtraFromUser, totalDebtToken);

        // “LP로 갚을 수 있는 양 + 유저 최소 추가분” 이 이론적으로는 빚 이상이어야 함
        // (lpBorrow >= debt 인 케이스도 허용하기 위해 >= 로 체크)
        assertGe(
            lpBorrowTokenAmount + minExtraFromUser,
            totalDebtToken,
            "lpBorrow + minExtra must cover totalDebt"
        );

        // LP에서 나오는 토큰이 둘 다 0이면 이상함 (성공 케이스에서는 어느 한 쪽은 > 0)
        assertTrue(
            amount0FromLp > 0 || amount1FromLp > 0,
            "preview: LP must return some tokens"
        );

        // ---------- 콘솔 출력 (프론트에서 보여줄 느낌) ----------

        console2.log(
            "===== previewClosePosition(tokenId =",
            tokenId,
            ") ====="
        );
        console2.log("vault          :", vaultOut);
        console2.log("supplyAsset(A) :", supplyAssetOut);
        console2.log("borrowAsset(B) :", borrowAssetOut);

        console2.log("Aave total debt (B)          :", totalDebtToken);
        console2.log("LP withdraw amount0 (raw)    :", amount0FromLp);
        console2.log("LP withdraw amount1 (raw)    :", amount1FromLp);
        console2.log("LP + swap -> borrowAsset (B) :", lpBorrowTokenAmount);

        console2.log("Extra B needed (min)         :", minExtraFromUser);
        console2.log("Extra B needed (max)         :", maxExtraFromUser);
    }

    /// @dev collectFee 0인 경우
    function test_CollectFees_HappyPath_WhenNoFeeAccured() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) 유저가 바로 collectFees 호출
        vm.startPrank(user);

        (uint256 collected0, uint256 collected1) = strategyRouter.collectFees(
            tokenId
        );

        assertEq(collected0, 0, "fee must be 0");
        assertEq(collected1, 0, "fee must be 0");
    }

    /// -------< Revert/Guard Cases >--------------

    /// @dev openPosition -> (trader swap) ->  closePosition 호출 성공 후
    ///      이미 닫힌 포지션 재호출
    function test_ClosePosition_Revert_WhenPositionAlreadyClosed() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset 부족분 보유
        deal(address(borrowToken), user, 1000e18);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);

        // 부족분 상한 만큼 미리 approve
        // 유저가 부족분 상한(maxExtraFromUser)만큼 미리 approve
        vm.startPrank(user);
        IERC20(address(borrowToken)).approve(
            address(strategyRouter),
            maxExtraFromUser
        );
        vm.stopPrank();

        // 4) User closePosition
        vm.startPrank(user);
        vm.expectEmit(true, true, true, false, address(strategyRouter));
        emit PositionClosed(
            user,
            vault,
            tokenId,
            address(supplyToken),
            address(borrowToken),
            /* collateralOut     */ 0,
            /* leftoverBorrow    */ 0
        );

        strategyRouter.closePosition(tokenId);

        // 5) 같은 포지션을 다시 닫으려 하면 실패해야 함 (isOpen=false)

        vm.expectRevert(StrategyRouter.PositionNotOpen.selector);
        strategyRouter.closePosition(tokenId);
        vm.stopPrank();
    }

    /// @dev openPosition -> (trader swap) ->  closePosition 호출 성공 후
    ///      이미 닫힌 포지션을 previewClosePosition 호출 시도
    function test_PreviewClosePosition_Revert_WhenPositionAlreadyClosed()
        public
    {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset 부족분 보유
        deal(address(borrowToken), user, 1000e18);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);

        // 부족분 상한 만큼 미리 approve
        // 유저가 부족분 상한(maxExtraFromUser)만큼 미리 approve
        vm.startPrank(user);
        IERC20(address(borrowToken)).approve(
            address(strategyRouter),
            maxExtraFromUser
        );
        vm.stopPrank();

        // 4) User closePosition
        vm.startPrank(user);
        vm.expectEmit(true, true, true, false, address(strategyRouter));
        emit PositionClosed(
            user,
            vault,
            tokenId,
            address(supplyToken),
            address(borrowToken),
            /* collateralOut     */ 0,
            /* leftoverBorrow    */ 0
        );

        strategyRouter.closePosition(tokenId);

        // 5) 이후 previewClosePosition 호출 시도

        vm.expectRevert(StrategyRouter.PositionNotOpen.selector);
        strategyRouter.previewClosePosition(tokenId);
        vm.stopPrank();
    }

    /// @dev openPosition -> (trader swap) ->  충분한 borrowToken을 approve하지 않았을 경우
    function test_ClosePosition_Revert_WhenUserInsufficientApproved() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset 부족분 보유
        deal(address(borrowToken), user, 1000e18);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);

        // 유저가 미리 1 approve
        vm.startPrank(user);

        IERC20(address(borrowToken)).approve(address(strategyRouter), 1);

        // 4) closePosition 시도

        vm.expectRevert();
        strategyRouter.closePosition(tokenId);
    }

    /// @dev openPosition -> (trader swap) ->  충분한 borrowToken을 owner가 소유하지 못할경우
    function test_ClosePosition_Revert_WhenUserHasNotEnoughBorrowedToken()
        public
    {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset을 매우 작게 보유
        deal(address(borrowToken), user, 100);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);

        // 유저가 미리 1 approve
        vm.startPrank(user);

        IERC20(address(borrowToken)).approve(
            address(strategyRouter),
            maxExtraFromUser
        );

        // 4) closePosition 시도

        vm.expectRevert();
        strategyRouter.closePosition(tokenId);
    }

    /// @dev openPosition -> (trader swap) ->  다른 유저가 closePosition 호출 시도
    function test_ClosePosition_Revert_WhenNotOwner() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저 토큰 잔고 스냅샷 (닫기 전)
        uint256 userSupplyBefore = IERC20(address(supplyToken)).balanceOf(user);
        uint256 userBorrowBefore = IERC20(address(borrowToken)).balanceOf(user);

        // 유저가 미리 borrowAsset 부족분 보유
        deal(address(borrowToken), user, 1000e18);

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 10);

        // 3) 미리 부족분에 대한 토큰양 확인 후 approve
        (
            ,
            ,
            ,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            ,

        ) = strategyRouter.previewClosePosition(tokenId);

        // 부족분 상한 만큼 미리 approve
        // 유저가 부족분 상한(maxExtraFromUser)만큼 미리 approve
        vm.startPrank(user);
        IERC20(address(borrowToken)).approve(
            address(strategyRouter),
            maxExtraFromUser
        );
        vm.stopPrank();

        // 4) 다른 User closePosition
        address other = makeAddr("other");
        vm.startPrank(other);
        // 5) 같은 포지션을 다시 닫으려 하면 실패해야 함 (isOpen=false)

        vm.expectRevert(StrategyRouter.NotPositionOwner.selector);
        strategyRouter.closePosition(tokenId);
        vm.stopPrank();
    }

    /// @dev 다른 사용자가 수수료 수령 시도
    function test_CollectFees_Revert_WhenNotPositionOwner() public {
        // 1) Call openPosition
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        (
            address vault,
            uint256 tokenId,
            uint256 collateralBefore,
            uint256 debtBefore,
            uint256 hfBefore
        ) = _openPositionFor(user, supplyAmount);

        // 2) Simulate Traders swapping in pool so LP position accures fees
        address trader = makeAddr("trader");
        _generateFeesByExternalSwaps(trader, 10e18, 20);

        // 3) 다른 유저 가 직접 collectFees 호출
        address other = makeAddr("other");
        vm.startPrank(other);
        vm.expectRevert(StrategyRouter.NotPositionOwner.selector);
        (uint256 collected0, uint256 collected1) = strategyRouter.collectFees(
            tokenId
        );
    }

    /// -------< Helper Functions >--------------

    /// @dev HookMiner를 사용해서 Hook 주소와 salt를 찾고, CREATE2로 배포 + PoolKey까지 생성
    function _deployHook()
        internal
        returns (SwapPriceLoggerHook _hook, PoolKey memory key)
    {
        // 1) 훅 생성 코드 + 생성자 인자 준비
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        bytes memory constructorArgs = abi.encode(address(uniPoolManager));

        // 2) 원하는 플래그로 Hook 주소 / Salt 찾기
        (address expectedHookAddr, bytes32 salt) = HookMiner.find({
            deployer: address(this),
            flags: uint160(Hooks.AFTER_SWAP_FLAG),
            creationCode: creationCode,
            constructorArgs: constructorArgs
        });

        // 3) CREATE2로 훅 배포
        _hook = new SwapPriceLoggerHook{salt: salt}(address(uniPoolManager));

        console2.log("EXPECTED HOOK :::", expectedHookAddr);
        console2.log("HOOK DEPLOYED :::", address(_hook));

        // 4) 테스트 환경 : deployer == address(this)

        assertEq(address(_hook), expectedHookAddr, "hook address mismatch");

        // 5) 이 훅 주소를 PoolKey에 세팅
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

    /// @dev user 수수료 수취 목적임의의 유저가 Swap N회 실행
    function _generateFeesByExternalSwaps(
        address trader,
        uint256 amountPerSwap,
        uint256 swapCount
    ) internal {
        // trader에 token0 지급
        deal(poolToken0, trader, amountPerSwap * swapCount * 2);

        vm.startPrank(trader);

        for (uint256 i; i < swapCount; ++i) {
            bool zeroForOne = (i % 2 == 0);
            // token0 -> token1 / token1 -> token0 번갈아가며

            address inToken = zeroForOne ? poolToken0 : poolToken1;
            IERC20(inToken).approve(address(miniRouter), amountPerSwap);

            // poolId, 이벤트 시그니처만 체크 (tick/price/timestamp는 안 봄)
            // poolId, 시그니처만 체크하고 싶으면:

            PoolId poolId = poolKey.toId();
            vm.expectEmit(true, true, false, false, address(hook));
            emit SwapPriceLogged(poolId, 0, 0, 0);

            Miniv4SwapRouter.ExactInputSingleParams
                memory params = Miniv4SwapRouter.ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: zeroForOne,
                    amountIn: uint128(amountPerSwap),
                    amountOutMin: 0,
                    hookData: bytes("")
                });
            miniRouter.swapExactInputSingle(params);
        }
        vm.stopPrank();
    }

    /// @dev openPosition 내장 함수
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
        // 0) 사전 상태: vault 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // v4 포지션 토큰 아이디 before 스냅샷
        uint256 nextIdBefore = uniPositionManager.nextTokenId();

        // 1) 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // 2) 유저가 openPosition 호출
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);
        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset
            supplyAmount, // supplyAmount
            address(borrowToken), // borrowAsset
            0 // targetHF1e18 (테스트용 고정값)
        );
        vm.stopPrank();

        // 3) vault 생성 확인
        vault = factory.accountOf(user);
        assertTrue(
            vault != address(0),
            "vault should exist after openPosition"
        );

        // 4) Aave 포지션(담보/부채) 검증
        IPool pool = IPool(aavePoolAddressProvider.getPool());
        (totalCollateralBase, totalDebtBase, , , , healthFactor) = pool
            .getUserAccountData(vault);

        assertGt(totalCollateralBase, 0, "vault must have collateral on Aave");
        assertGt(totalDebtBase, 0, "vault must have debt on Aave");
        assertGt(healthFactor, 0, "HF must be > 0");

        // 5) Uniswap v4 LP 포지션 검증
        uint256 nextIdAfter = uniPositionManager.nextTokenId();
        assertEq(
            nextIdAfter,
            nextIdBefore + 1,
            "exactly one new LP NFT should be minted"
        );

        newTokenId = nextIdAfter - 1;

        uint128 liq = uniPositionManager.getPositionLiquidity(newTokenId);
        assertGt(liq, 0, "LP liquidity must be > 0");
    }

    /// @dev 페어에 대한 PoolKey 생성
    function _buildPoolKey(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing,
        IHooks hooks
    ) internal pure returns (PoolKey memory key) {
        // 1) 토큰 주소 정렬
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

        // 2) PoolKey 생성
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: _fee,
            tickSpacing: _tickSpacing,
            hooks: hooks
        });
    }

    /// @dev 풀 생성(Initialize) 후  초기 tick 반환
    function _initPool(
        PoolKey memory key,
        uint160 sqrtPriceX96
    ) internal returns (int24 initTick) {
        initTick = uniPoolManager.initialize(key, sqrtPriceX96);
        console2.log("Initialized Tick : ", initTick);
    }

    /// @dev PositionManager를 통해 유동성 공급
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
        permit2.approve(t0, address(uniPositionManager), max160, neverExpire);
        permit2.approve(t1, address(uniPositionManager), max160, neverExpire);

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

        uint256 beforeId = uniPositionManager.nextTokenId();
        uint256 bal0Before = IERC20(t0).balanceOf(provider);
        uint256 bal1Before = IERC20(t1).balanceOf(provider);

        uniPositionManager.modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        // 5) Verification
        uint256 afterId = uniPositionManager.nextTokenId();
        uint256 bal0After = IERC20(t0).balanceOf(provider);
        uint256 bal1After = IERC20(t1).balanceOf(provider);

        tokenId = beforeId;
        spent0 = bal0Before - bal0After;
        spent1 = bal1Before - bal1After;
    }
}
