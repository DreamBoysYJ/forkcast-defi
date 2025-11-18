// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

// Commons
import {IERC20, IERC20Metadata} from "../src/interfaces/IERC20.sol";

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

contract StrategyRouterOpenPosition is Test {
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

    // Actors
    address internal admin;

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

        uint24 _fee = 3000;
        int24 _tickSpacing = 10;
        IHooks hooks = IHooks(address(0));

        PoolKey memory key = _buildPoolKey(
            address(supplyToken),
            address(borrowToken),
            _fee,
            _tickSpacing,
            hooks
        );

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

    /// @dev openPosition 최초 호출 성공
    function test_OpenPosition_HappyPath() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // v4 포지션 토큰 아이디 before 스냅샷
        uint256 nextIdBefore = uniPositionManager.nextTokenId();

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);
        vm.expectEmit(true, false, false, false, address(strategyRouter));
        emit PositionOpened(
            user,
            address(0), // vault는 실제론 다르지만, 어차피 안 볼 거라 대충 0
            address(0),
            0,
            address(0),
            0,
            0,
            0,
            0,
            0,
            0
        );

        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset
            supplyAmount, // supplyAmount
            address(borrowToken), // borrowAsset
            2.1e18 // 0이면 라우터 기본값(예: 1.35e18) 사용
        );
        vm.stopPrank();

        // -------- 3) vault 생성 확인 --------
        address vault = factory.accountOf(user);
        assertTrue(
            vault != address(0),
            "vault should exist after openPosition"
        );

        // -------- 4) Aave 포지션(담보/부채) 검증 --------
        IPool pool = IPool(aavePoolAddressProvider.getPool());

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,
            uint256 healthFactor
        ) = pool.getUserAccountData(vault);

        assertGt(totalCollateralBase, 0, "vault must have collateral on Aave");
        assertGt(totalDebtBase, 0, "vault must have debt on Aave");
        assertGt(healthFactor, 0, "HF must be > 0");

        // -------- 5) Uniswap v4 LP 포지션 검증 --------
        uint256 nextIdAfter = uniPositionManager.nextTokenId();
        // 부트스트랩용 LP는 이미 setUp에서 하나 민트했으니,
        // openPosition 이후에는 딱 1개 더 늘어나야 정상
        assertEq(
            nextIdAfter,
            nextIdBefore + 1,
            "exactly one new LP NFT should be minted"
        );

        uint256 newTokenId = nextIdAfter - 1;
        // address owner = uniPositionManager.ownerOf(newTokenId);
        // assertEq(owner, vault, "new LP NFT owner must be the vault");

        // -------- 6) (선택) 디버그 로그 --------
        console2.log("user vault        :", vault);
        console2.log("collateral base   :", totalCollateralBase);
        console2.log("debt base         :", totalDebtBase);
        console2.log("health factor     :", healthFactor);
        console2.log("new LP tokenId    :", newTokenId);

        uint128 afterLiquidity = uniPositionManager.getPositionLiquidity(
            newTokenId
        );
        console2.log("LIQUIDITY IN POOL AFTER USER IN :", afterLiquidity);
    }

    /// @dev openPosition 후 다시 openPosition 호출
    ///      1개 금고가 여러 포지션 LP를 소유할 수 있는지 체크
    function test_OpenPosition_ReuseExistingVault_Succeeds() public {
        // 1) 최초 openPosition 성공

        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // v4 포지션 토큰 아이디 before 스냅샷
        uint256 nextIdBefore = uniPositionManager.nextTokenId();

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset
            supplyAmount, // supplyAmount
            address(borrowToken), // borrowAsset
            0 // targetHF1e18: 0이면 라우터 기본값(예: 1.35e18) 사용
        );

        // -------- 3) vault 생성 확인 --------
        address vault = factory.accountOf(user);
        assertTrue(
            vault != address(0),
            "vault should exist after openPosition"
        );

        // -------- 4) Aave 포지션(담보/부채) 검증 --------
        IPool pool = IPool(aavePoolAddressProvider.getPool());

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,
            uint256 healthFactor
        ) = pool.getUserAccountData(vault);

        assertGt(totalCollateralBase, 0, "vault must have collateral on Aave");
        assertGt(totalDebtBase, 0, "vault must have debt on Aave");
        assertGt(healthFactor, 0, "HF must be > 0");

        // -------- 5) Uniswap v4 LP 포지션 검증 --------
        uint256 nextIdAfter = uniPositionManager.nextTokenId();
        // 부트스트랩용 LP는 이미 setUp에서 하나 민트했으니,
        // openPosition 이후에는 딱 1개 더 늘어나야 정상
        assertEq(
            nextIdAfter,
            nextIdBefore + 1,
            "exactly one new LP NFT should be minted"
        );

        uint256 newTokenId = nextIdAfter - 1;
        // address owner = uniPositionManager.ownerOf(newTokenId);
        // assertEq(owner, vault, "new LP NFT owner must be the vault");
        // -------- 6) (선택) 디버그 로그 --------
        console2.log("user vault        :", vault);
        console2.log("collateral base   :", totalCollateralBase);
        console2.log("debt base         :", totalDebtBase);
        console2.log("health factor     :", healthFactor);
        console2.log("new LP tokenId    :", newTokenId);

        uint128 afterLiquidity = uniPositionManager.getPositionLiquidity(
            newTokenId
        );
        console2.log("LIQUIDITY IN POOL AFTER USER IN :", afterLiquidity);

        // 2. 유저가 다시 openPosition

        // 1). 유저 세팅
        uint256 supplyAmountRe = 500e18;
        deal(address(supplyToken), user, supplyAmountRe);

        // 이미 금고 존재해야
        vaultBefore = factory.accountOf(user);
        assertNotEq(vaultBefore, address(0));

        // 포지션 토큰 스냅샷
        uint256 nextTokenId = uniPositionManager.nextTokenId();

        // 2) openPosition 호출
        supplyToken.approve(address(strategyRouter), supplyAmountRe);

        strategyRouter.openPosition(
            address(supplyToken),
            supplyAmountRe,
            address(borrowToken),
            1.5e18
        );

        // 3) 금고 그대로 여야
        assertEq(
            vaultBefore,
            factory.accountOf(user),
            "vault must be created once"
        );

        // 4) Aave 포지션 (담보/부채 검증)
        IPool poolAfter = IPool(aavePoolAddressProvider.getPool());
        (
            uint256 totalCollateralBaseAfter,
            uint256 totalDebtBaseAfter,
            ,
            ,
            ,
            uint256 healthFactorAfter
        ) = pool.getUserAccountData(vaultBefore);

        assertGt(
            totalCollateralBaseAfter,
            totalCollateralBase,
            "total collabse must be increase"
        );
        assertGt(
            totalDebtBaseAfter,
            totalDebtBase,
            "total collabse must be increase"
        );
        assertGt(healthFactorAfter, healthFactor, "HF must be increase");

        // 5) Uniswap LP 포지션 검증
        uint256 nextTokenIdAfter = uniPositionManager.nextTokenId();
        assertEq(
            nextTokenId + 1,
            nextTokenIdAfter,
            "Token must be not increased"
        );

        uint128 liquidityAfter = uniPositionManager.getPositionLiquidity(
            nextTokenId
        );
        console2.log(
            "LIQUIDITY IN POOL AFTER USER CALL TWICE :",
            liquidityAfter
        );
    }

    /// -------< Revert/Guard Cases >--------------

    /// @dev supplyAsset == address(0)
    function test_OpenPosition_Revert_ZeroSupplyAsset() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        vm.expectRevert(AaveModule.ZeroAddress.selector);

        strategyRouter.openPosition(
            address(0), // supplyAsset == address(0)
            supplyAmount, // supplyAmount
            address(borrowToken), // borrowAsset
            0 // targetHF1e18: 0이면 라우터 기본값(예: 1.35e18) 사용
        );
        vm.stopPrank();
    }

    /// @dev borrowAsset == address(0)
    function test_OpenPosition_Revert_ZeroBorrowAsset() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        vm.expectRevert(AaveModule.ZeroAddress.selector);

        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset == address(0)
            supplyAmount, // supplyAmount
            address(0), // borrowAsset
            0 // targetHF1e18: 0이면 라우터 기본값(예: 1.35e18) 사용
        );
        vm.stopPrank();
    }

    /// @dev supplyAsset is Not Approved beforehand
    function test_OpenPosition_Revert_SupplyAssetNotApproved() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        // supplyToken.approve(address(strategyRouter), supplyAmount);

        vm.expectRevert();

        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset == address(0)
            supplyAmount, // supplyAmount
            address(borrowToken), // supplyAsset == address(0)
            0 // targetHF1e18: 0이면 라우터 기본값(예: 1.35e18) 사용
        );
        vm.stopPrank();
    }

    /// @dev borrowingEnabled == false
    function test_OpenPosition_Revert_WhenBorringDisabledFlagOff() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        // 2) Aave reserve Config MOCK
        // IAaveProtocolDataProvider.getReserveConfigurationData(asset) 시그니처 기준:
        // (uint256,uint256,uint256,uint256,uint256,
        //  bool usageAsCollateral,
        //  bool borrowingEnabled,
        //  bool stableRateBorrowingEnabled,
        //  bool isActive,
        //  bool isFrozen)
        vm.mockCall(
            address(aaveProtocolDataProvider),
            abi.encodeWithSelector(
                IAaveProtocolDataProvider.getReserveConfigurationData.selector,
                address(borrowToken)
            ),
            abi.encode(
                uint256(18), // decimals
                uint256(0), // ltv
                uint256(0), // liqThreshold
                uint256(0), // liqBonus
                uint256(0), // reserveFactor
                true, // usageAsCollateral
                false, // borrowingEnabled = false  <<<<<
                true, // stableRateBorrowingEnabled
                true, // isActive
                false // isFrozen
            )
        );

        // 3) expectRevert. BorrowingDisabled
        vm.expectRevert(AaveModule.BorrowingDisabled.selector);

        strategyRouter.openPosition(
            address(supplyToken),
            supplyAmount,
            address(borrowToken),
            0 // targetHF1e18 (0 → 기본값)
        );

        vm.stopPrank();
    }

    /// @dev supplyingEnabled == false
    function test_OpenPosition_Revert_WhenSupplyingDisabledFlagOff() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18;

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        // 2) Aave reserve Config MOCK
        // IAaveProtocolDataProvider.getReserveConfigurationData(asset) 시그니처 기준:
        // (uint256,uint256,uint256,uint256,uint256,
        //  bool usageAsCollateral,
        //  bool supplyingEnabled,
        //  bool stableRatesupplyingEnabled,
        //  bool isActive,
        //  bool isFrozen)
        vm.mockCall(
            address(aaveProtocolDataProvider),
            abi.encodeWithSelector(
                IAaveProtocolDataProvider.getReserveConfigurationData.selector,
                address(supplyToken)
            ),
            abi.encode(
                uint256(18),
                uint256(0),
                uint256(0),
                uint256(0),
                uint256(0),
                false, // usageAsCollateralEnabled = false  <<< 여기!
                true, // borrowingEnabled (supply에는 영향 X)
                true, // stableRateBorrowingEnabled
                true, // isActive
                false // isFrozen
            )
        );

        // 3) expectRevert. BorrowingDisabled
        vm.expectRevert(AaveModule.SupplyingDisabled.selector);

        strategyRouter.openPosition(
            address(supplyToken),
            supplyAmount,
            address(borrowToken),
            0 // targetHF1e18 (0 → 기본값)
        );

        vm.stopPrank();
    }

    /// @dev supplyAmount == 0
    function test_OpenPosition_Revert_ZeroSupplyAmount() public {
        // -------- 1) 유저 세팅 --------
        address user = makeAddr("user");
        uint256 supplyAmount = 100e18; // 너무 크면 세폴리아 유동성 따라 줄여도 됨

        // 유저에게 supply 토큰 지급
        deal(address(supplyToken), user, supplyAmount);

        // openPosition 호출 전에는 vault가 없어야 정상
        address vaultBefore = factory.accountOf(user);
        assertEq(
            vaultBefore,
            address(0),
            "vault should not exist before openPosition"
        );

        // -------- 2) 유저가 openPosition 호출 --------
        vm.startPrank(user);
        supplyToken.approve(address(strategyRouter), supplyAmount);

        vm.expectRevert(AaveModule.ZeroAmount.selector);

        strategyRouter.openPosition(
            address(supplyToken), // supplyAsset == address(0)
            0, // supplyAmount <<< 000000000
            address(borrowToken), // borrowAsset
            0 // targetHF1e18: 0이면 라우터 기본값(예: 1.35e18) 사용
        );
        vm.stopPrank();
    }

    /// @dev borrowAmount = 0 일 경우 revert
    // NOTE: ZeroBorrowAfterSafety:
    // extremely edge-case (HF/caps/liquidity rounding → finalToken == 0).
    // For now we rely on internal math; integration test omitted.
    // TODO: if needed, cover with unit test + mocked Aave/Oracle.

    /// -------< Helper Functions >--------------

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
