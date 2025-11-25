// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Common
import {IERC20, IERC20Metadata} from "../interfaces/IERC20.sol";

// Forkcast-Defi
import {UserAccount} from "../accounts/UserAccount.sol";
import {AccountFactory} from "../factory/AccountFactory.sol";
import {StrategyRouter} from "../router/StrategyRouter.sol";

// Aave
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {
    IAaveProtocolDataProvider
} from "../interfaces/aave-v3/IAaveProtocolDataProvider.sol";
import {
    IPoolAddressesProvider
} from "../interfaces/aave-v3/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "../interfaces/aave-v3/IPriceOracleGetter.sol";

// Uniswap V4
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {
    LiquidityAmounts
} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {
    IPositionManager
} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {
    PositionInfo,
    PositionInfoLibrary
} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";

contract StrategyLens {
    address public admin;

    // -------- AAVE 관련 --------
    IPoolAddressesProvider public immutable AAVE_ADDRESSES_PROVIDER;
    IAaveProtocolDataProvider public immutable AAVE_DATA_PROVIDER;
    IPool public immutable AAVE_POOL;
    IPriceOracleGetter public immutable AAVE_ORACLE;

    // -------- Uniswap V4 관련 --------
    IPoolManager public immutable UNI_POOL_MANAGER;
    IPositionManager public immutable UNI_POSITION_MANAGER;

    // -------- Forkcast 전용 --------
    AccountFactory public immutable ACCOUNT_FACTORY;
    StrategyRouter public immutable STRATEGY_ROUTER;

    //  ----------------- AAVE Structs -----------------

    /// @dev 유저 전체 Aave 상태 요약
    struct UserAaveOverview {
        address user;
        address vault;
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    /// @dev 유저가 특정 asset을 기준으로 Aave에서 어떤 포지션 들고 있는지
    struct UserReservePosition {
        address asset;
        uint256 aTokenBalance;
        uint256 stableDebt;
        uint256 variableDebt;
    }

    /// @dev 리저브 메타 정보(+캡, paused 상태)
    struct ReserveStaticData {
        address asset;
        string symbol;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        bool usageAsCollateralEnabled;
        bool borrowingEnabled;
        bool stableBorrowRateEnabled;
        bool isActive;
        bool isFrozen;
        uint256 borrowCap;
        uint256 supplyCap;
        address aToken;
        address stableDebtToken;
        address variableDebtToken;
        bool paused;
    }

    /// @dev 내부 헬퍼용: 리저브 설정값 모음
    struct ReserveConfigView {
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        bool usageAsCollateralEnabled;
        bool borrowingEnabled;
        bool stableBorrowRateEnabled;
        bool isActive;
        bool isFrozen;
    }

    /// @dev 내부 헬퍼용: 토큰 주소들
    struct ReserveTokensView {
        address aToken;
        address stableDebtToken;
        address variableDebtToken;
    }

    /// @dev 내부 헬퍼용: 캡 + paused
    struct ReserveCapsView {
        uint256 borrowCap;
        uint256 supplyCap;
        bool paused;
    }

    /// 금리(APY) 관련
    struct ReserveRateData {
        address asset;
        string symbol; // 👈 이거 반드시 들어가야 함
        uint256 liquidityRateRay; // 예치 금리 (RAY)
        uint256 variableBorrowRateRay; // 변동 대출 금리 (RAY)
        uint256 stableBorrowRateRay; // 고정 대출 금리 (RAY)
    }

    /// 가격 관련
    struct AssetPriceData {
        address asset;
        // BASE_CURRENCY 기준 가격 (Aave Oracle 단위 그대로)
        uint256 priceInBaseCurrency;
    }

    //  ----------------- Uniswap Structs -----------------
    /// 유니스왑 포지션 + 풀 정보
    struct UniPositionOverview {
        address token0;
        address token1;
        uint128 liquidity;
        uint256 amount0Now;
        uint256 amount1Now;
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;
        uint160 sqrtPriceX96;
    }

    /// @dev Router에 저장된 기본 포지션 정보(내부 PositionInfo의 축약 버전)
    struct RouterPositionCore {
        address owner;
        address vault;
        address supplyAsset;
        address borrowAsset;
        bool isOpen;
    }

    /// @dev 한 전략 포지션에 대한 "통합 뷰"
    ///      - Router 메타 정보
    ///      - Uniswap v4 포지션 요약
    ///      - Aave 계정 상태 요약
    struct StrategyPositionView {
        RouterPositionCore core;
        // Uniswap v4 관련
        address uniToken0;
        address uniToken1;
        uint128 liquidity;
        uint256 amount0Now; // 지금 전부 빼면 받는 token0
        uint256 amount1Now; // 지금 전부 빼면 받는 token1
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;
        uint160 sqrtPriceX96;
        // Aave 계정 요약 (vault 기준)
        uint256 totalCollateralBase;
        uint256 totalDebtBase;
        uint256 availableBorrowBase;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }

    constructor(
        address _admin,
        address _aaveAddressesProvider,
        address _aavePool,
        address _aaveDataProvdier,
        address _accountFactory,
        address _aaveOracle,
        address _uniPoolManager,
        address _uniPositionManager,
        address _strategyRouter
    ) {
        admin = _admin;

        // Aave
        AAVE_ADDRESSES_PROVIDER = IPoolAddressesProvider(
            _aaveAddressesProvider
        );
        AAVE_DATA_PROVIDER = IAaveProtocolDataProvider(_aaveDataProvdier);
        AAVE_POOL = IPool(_aavePool);
        AAVE_ORACLE = IPriceOracleGetter(_aaveOracle);

        // Uniswap
        UNI_POOL_MANAGER = IPoolManager(_uniPoolManager);
        UNI_POSITION_MANAGER = IPositionManager(_uniPositionManager);

        // Forkcast
        ACCOUNT_FACTORY = AccountFactory(_accountFactory);
        STRATEGY_ROUTER = StrategyRouter(_strategyRouter);
    }

    // -------- AAVE 관련 함수 --------

    // ----------------- 1) 유저 → 볼트 조회 -----------------
    /// @notice 지갑 주소로 UserAccount(Valut) 주소 조회
    /// @dev    포지션 없으면 vault == address(0)
    function getUserVault(address user) public view returns (address vault) {
        vault = ACCOUNT_FACTORY.accountOf(user);
    }

    // ----------------- 2) 유저 Aave 전체 요약 -----------------

    /// @notice 유저의 Aave 전체 포지션 요약 (HF, 담보/부채, vault )
    /// @dev    프론트에서 '대시보드 상단 카드'에 그대로 넣을 데이터
    function getUserAaveOverview(
        address user
    ) external view returns (UserAaveOverview memory ov) {
        address vault = ACCOUNT_FACTORY.accountOf(user);

        if (vault == address(0)) {
            ov = UserAaveOverview({
                user: user,
                vault: address(0),
                totalCollateralBase: 0,
                totalDebtBase: 0,
                availableBorrowBase: 0,
                currentLiquidationThreshold: 0,
                ltv: 0,
                healthFactor: 0
            });
            return ov;
        }

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = AAVE_POOL.getUserAccountData(vault);

        ov = UserAaveOverview({
            user: user,
            vault: vault,
            totalCollateralBase: totalCollateralBase,
            totalDebtBase: totalDebtBase,
            availableBorrowBase: availableBorrowsBase,
            currentLiquidationThreshold: currentLiquidationThreshold,
            ltv: ltv,
            healthFactor: healthFactor
        });
    }

    // ----------------- 3) 리저브 메타데이터 (전역) -----------------

    /// @notice Aave 상의 모든 리저브(토큰)에 대한 설정/상태 정보
    /// @dev    프론트에서 '지원 자산 리스트 + LTV, Caps, Paused 여부' 보여줄 때 사용
    function getAllAaveReserves()
        external
        view
        returns (ReserveStaticData[] memory reserves)
    {
        IAaveProtocolDataProvider.TokenData[] memory tokens = AAVE_DATA_PROVIDER
            .getAllReservesTokens();

        reserves = new ReserveStaticData[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            reserves[i] = _getReserveStaticData(
                tokens[i].tokenAddress,
                tokens[i].symbol
            );
        }
    }

    /// @dev 내부에서 struct 3개에 나눠 담아서 stack depth 줄이기
    function _getReserveStaticData(
        address asset,
        string memory symbol
    ) internal view returns (ReserveStaticData memory r) {
        ReserveConfigView memory cfg = _getReserveConfigData(asset);
        ReserveTokensView memory t = _getReserveTokensData(asset);
        ReserveCapsView memory caps = _getReserveCapsData(asset);

        r = ReserveStaticData({
            asset: asset,
            symbol: symbol,
            decimals: cfg.decimals,
            ltv: cfg.ltv,
            liquidationThreshold: cfg.liquidationThreshold,
            liquidationBonus: cfg.liquidationBonus,
            reserveFactor: cfg.reserveFactor,
            usageAsCollateralEnabled: cfg.usageAsCollateralEnabled,
            borrowingEnabled: cfg.borrowingEnabled,
            stableBorrowRateEnabled: cfg.stableBorrowRateEnabled,
            isActive: cfg.isActive,
            isFrozen: cfg.isFrozen,
            borrowCap: caps.borrowCap,
            supplyCap: caps.supplyCap,
            aToken: t.aToken,
            stableDebtToken: t.stableDebtToken,
            variableDebtToken: t.variableDebtToken,
            paused: caps.paused
        });
    }

    /// @dev Aave DataProvider: getReserveConfigurationData
    function _getReserveConfigData(
        address asset
    ) internal view returns (ReserveConfigView memory cfg) {
        (
            cfg.decimals,
            cfg.ltv,
            cfg.liquidationThreshold,
            cfg.liquidationBonus,
            cfg.reserveFactor,
            cfg.usageAsCollateralEnabled,
            cfg.borrowingEnabled,
            cfg.stableBorrowRateEnabled,
            cfg.isActive,
            cfg.isFrozen
        ) = AAVE_DATA_PROVIDER.getReserveConfigurationData(asset);
    }

    /// @dev Aave DataProvider: getReserveTokensAddresses
    function _getReserveTokensData(
        address asset
    ) internal view returns (ReserveTokensView memory t) {
        (t.aToken, t.stableDebtToken, t.variableDebtToken) = AAVE_DATA_PROVIDER
            .getReserveTokensAddresses(asset);
    }

    /// @dev Aave DataProvider: getReserveCaps + getPaused(try/catch)
    function _getReserveCapsData(
        address asset
    ) internal view returns (ReserveCapsView memory caps) {
        (caps.borrowCap, caps.supplyCap) = AAVE_DATA_PROVIDER.getReserveCaps(
            asset
        );

        // 배포에 따라 없을 수 있으니 try/catch
        try AAVE_DATA_PROVIDER.getPaused(asset) returns (bool isPaused) {
            caps.paused = isPaused;
        } catch {
            caps.paused = false;
        }
    }

    // ----------------- 4) 유저 개별 리저브 포지션 -----------------

    /// @notice 유저가 주어진 asset 리스트에 대해 Aave에서 들고 있는 예치/부채 잔고 조회
    /// @dev 프론트에서 “내 포지션 - 토큰별 상세 테이블” 용
    ///         - assets : 예) [AAVE, WBTC]
    ///         - return : 각 asset에 대해 aToken/StableDebt/VariableDebt
    function getUserReservePositions(
        address user,
        address[] memory assets
    ) public view returns (UserReservePosition[] memory positions) {
        address vault = ACCOUNT_FACTORY.accountOf(user);
        positions = new UserReservePosition[](assets.length);

        if (vault == address(0)) {
            for (uint256 i = 0; i < assets.length; i++) {
                positions[i] = UserReservePosition({
                    asset: assets[i],
                    aTokenBalance: 0,
                    stableDebt: 0,
                    variableDebt: 0
                });
            }
            return positions;
        }

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            (
                address aToken,
                address stableDebtToken,
                address variableDebtToken
            ) = AAVE_DATA_PROVIDER.getReserveTokensAddresses(asset);

            uint256 aBal = aToken != address(0)
                ? IERC20(aToken).balanceOf(vault)
                : 0;
            uint256 sDebt = stableDebtToken != address(0)
                ? IERC20(stableDebtToken).balanceOf(vault)
                : 0;
            uint256 vDebt = variableDebtToken != address(0)
                ? IERC20(variableDebtToken).balanceOf(vault)
                : 0;

            positions[i] = UserReservePosition({
                asset: asset,
                aTokenBalance: aBal,
                stableDebt: sDebt,
                variableDebt: vDebt
            });
        }
    }

    // ----------------- 5) 유저 리저브 포지션 (전체 리저브 자동) -----------------

    /// @notice Aave에 등록된 모든 리저브에 대해 유저 포지션 조회
    /// @dev 프론트에서 "내 Aave 포지션 전체 보기" 버튼 누르면 이거 한 방에 호출하면 됨
    function getUserReservePositionsAll(
        address user
    ) external view returns (UserReservePosition[] memory positions) {
        IAaveProtocolDataProvider.TokenData[] memory tokens = AAVE_DATA_PROVIDER
            .getAllReservesTokens();

        address[] memory assets = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            assets[i] = tokens[i].tokenAddress;
        }

        positions = getUserReservePositions(user, assets);
    }

    // ----------------- 6) 리저브 금리(APY) -----------------

    /// @notice 단일 리저브의 금리 정보 (RAY 단위)
    function getReserveRates(
        address asset
    ) external view returns (ReserveRateData memory r) {
        (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        ) = AAVE_DATA_PROVIDER.getReserveData(asset); // v2 D
        // 단일 자산이니까 심볼은 그냥 ERC20 메타데이터에서 읽어오면 됨
        string memory symbol = IERC20Metadata(asset).symbol();

        r = ReserveRateData({
            asset: asset,
            symbol: symbol, // 👈 이 줄 추가
            liquidityRateRay: liquidityRate,
            variableBorrowRateRay: variableBorrowRate,
            stableBorrowRateRay: stableBorrowRate
        });
    }

    /// @notice 모든 리저브에 대한 금리 정보
    function getAllReserveRates()
        external
        view
        returns (ReserveRateData[] memory rates)
    {
        IAaveProtocolDataProvider.TokenData[] memory tokens = AAVE_DATA_PROVIDER
            .getAllReservesTokens();

        uint256 len = tokens.length;
        rates = new ReserveRateData[](len); // ✅ 반드시 new

        for (uint256 i = 0; i < len; ++i) {
            address asset = tokens[i].tokenAddress;

            (
                uint256 unbacked,
                uint256 accruedToTreasuryScaled,
                uint256 totalAToken,
                uint256 totalStableDebt,
                uint256 totalVariableDebt,
                uint256 liquidityRate,
                uint256 variableBorrowRate,
                uint256 stableBorrowRate,
                uint256 averageStableBorrowRate,
                uint256 liquidityIndex,
                uint256 variableBorrowIndex,
                uint40 lastUpdateTimestamp
            ) = AAVE_DATA_PROVIDER.getReserveData(asset); // v2 DataProvider는 여기까지 10개(return 10개)임

            rates[i].asset = asset;
            rates[i].symbol = tokens[i].symbol;
            rates[i].liquidityRateRay = liquidityRate;
            rates[i].variableBorrowRateRay = variableBorrowRate;
            rates[i].stableBorrowRateRay = stableBorrowRate;
        }
    }

    // ----------------- 7) Aave 오라클 가격 -----------------

    /// @notice 단일 자산 가격 (BASE_CURRENCY 기준)
    function getAssetPrice(address asset) external view returns (uint256) {
        return AAVE_ORACLE.getAssetPrice(asset);
    }

    /// @notice 여러 자산 가격 (asset + price 묶어서 리턴)
    function getAssetsPrices(
        address[] calldata assets
    ) external view returns (AssetPriceData[] memory prices) {
        uint256 len = assets.length;
        uint256[] memory rawPrices = AAVE_ORACLE.getAssetsPrices(assets);
        prices = new AssetPriceData[](len);

        for (uint256 i; i < len; ++i) {
            prices[i] = AssetPriceData({
                asset: assets[i],
                priceInBaseCurrency: rawPrices[i]
            });
        }
    }

    /// @notice 오라클 기준 통화 & 단위 (프론트에서 스케일링 계산용)
    function getOracleBaseCurrency()
        external
        view
        returns (address baseCurrency, uint256 baseUnit)
    {
        baseCurrency = AAVE_ORACLE.BASE_CURRENCY();
        baseUnit = AAVE_ORACLE.BASE_CURRENCY_UNIT();
    }

    // =========================================================
    //                  Uniswap V4 뷰 함수
    // =========================================================

    /// @notice 특정 유저 + tokenId 기준으로 Uniswap V4 포지션 상태 조회
    /// @dev    프론트에서 "내 포지션 카드" 하나 렌더링할 때 딱 쓰기 좋은 형태
    function getUserUniPosition(
        address user,
        uint256 tokenId
    ) external view returns (UniPositionOverview memory ov) {
        address vault = ACCOUNT_FACTORY.accountOf(user);
        if (vault == address(0)) {
            return ov;
        }

        // 1) StrategyRouter- previewUniPosition
        (
            address token0,
            address token1,
            uint128 liquidity,
            uint256 amount0Now,
            uint256 amount1Now,
            int24 tickLower,
            int24 tickUpper,
            int24 currentTick,
            uint160 sqrtPriceX96
        ) = STRATEGY_ROUTER.previewUniPosition(tokenId);

        // 2) struct에 담아서 반환
        ov = UniPositionOverview({
            token0: token0,
            token1: token1,
            liquidity: liquidity,
            amount0Now: amount0Now,
            amount1Now: amount1Now,
            tickLower: tickLower,
            tickUpper: tickUpper,
            currentTick: currentTick,
            sqrtPriceX96: sqrtPriceX96
        });
    }

    // =========================================================
    //                  통합 포지션 뷰 함수
    // =========================================================
    /// @notice tokenId 기준으로 이 전략 포지션의 전체 뷰를 한 번에 가져온다.
    /// @dev 프론트에서 "전략 상세 카드" 하나 그릴 때 이거 한 방에 쓰면 됨.
    function getStrategyPositionView(
        uint256 tokenId
    ) external view returns (StrategyPositionView memory v) {
        // 1) Router에 저장된 포지션 메타 정보 로딩
        RouterPositionCore memory core;
        (
            core.owner,
            core.vault,
            core.supplyAsset,
            core.borrowAsset,
            core.isOpen
        ) = STRATEGY_ROUTER.positions(tokenId);

        v.core = core;

        // vault가 없으면 (아직 포지션 없는 상태) 나머지는 전부 0으로 리턴
        if (core.vault == address(0)) {
            return v;
        }

        // 2) Uniswap v4 포지션 요약
        (
            v.uniToken0,
            v.uniToken1,
            v.liquidity,
            v.amount0Now,
            v.amount1Now,
            v.tickLower,
            v.tickUpper,
            v.currentTick,
            v.sqrtPriceX96
        ) = STRATEGY_ROUTER.previewUniPosition(tokenId);

        // 3) Aave 계정 상태 (vault 기준)
        (
            v.totalCollateralBase,
            v.totalDebtBase,
            v.availableBorrowBase,
            v.currentLiquidationThreshold,
            v.ltv,
            v.healthFactor
        ) = AAVE_POOL.getUserAccountData(core.vault);
    }
}
