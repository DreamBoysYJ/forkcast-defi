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

/// @title StrategyLens
/// @notice Read-only view layer for the Forkcast strategy: aggregates Aave, Uniswap v4, and router state into
///         front-end friendly structs. No state mutation, no protocol interaction beyond `view` calls.
contract StrategyLens {
    address public admin;

    // -------- AAVE --------
    IPoolAddressesProvider public immutable AAVE_ADDRESSES_PROVIDER;
    IAaveProtocolDataProvider public immutable AAVE_DATA_PROVIDER;
    IPool public immutable AAVE_POOL;
    IPriceOracleGetter public immutable AAVE_ORACLE;

    // -------- Uniswap V4 --------
    IPoolManager public immutable UNI_POOL_MANAGER;
    IPositionManager public immutable UNI_POSITION_MANAGER;

    // -------- Forkcast --------
    AccountFactory public immutable ACCOUNT_FACTORY;
    StrategyRouter public immutable STRATEGY_ROUTER;

    //  ----------------- AAVE Structs -----------------

    /// @dev High-level Aave account summary for a user (via vault).
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

    /// @dev Per-asset Aave position for a specific user vault.
    struct UserReservePosition {
        address asset;
        uint256 aTokenBalance;
        uint256 stableDebt;
        uint256 variableDebt;
    }

    /// @dev Static configuration and caps for a reserve (what the UI needs to decide "is this asset usable?").
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

    /// @dev Internal helper struct: reserve configuration slice (used to avoid stack-too-deep).
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

    /// @dev Internal helper struct: token addresses for a reserve.
    struct ReserveTokensView {
        address aToken;
        address stableDebtToken;
        address variableDebtToken;
    }

    /// @dev Internal helper struct: caps + `paused` flag.
    struct ReserveCapsView {
        uint256 borrowCap;
        uint256 supplyCap;
        bool paused;
    }

    /// @dev Rate data (in RAY) for a reserve.
    struct ReserveRateData {
        address asset;
        string symbol; // UI wants the symbol alongside the asset address.
        uint256 liquidityRateRay; // deposit APY (ray)
        uint256 variableBorrowRateRay; // variable borrow APY (ray)
        uint256 stableBorrowRateRay; // stable borrow APY (ray)
    }

    /// @dev Price for an asset in Aave's base currency.
    struct AssetPriceData {
        address asset;
        // BASE_CURRENCY based price (Aave Oracle)
        uint256 priceInBaseCurrency;
    }

    //  ----------------- Uniswap Structs -----------------

    /// @dev Uniswap v4 position snapshot plus pool price info.
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

    /// @dev Core router-managed metadata for a strategy position.
    struct RouterPositionCore {
        address owner;
        address vault;
        address supplyAsset;
        address borrowAsset;
        bool isOpen;
    }

    /// @dev Full strategy position view for one tokenId:
    ///      - Router metadata
    ///      - Uniswap v4 position snapshot
    ///      - Aave account summary (via vault)
    struct StrategyPositionView {
        RouterPositionCore core;
        // Uniswap v4
        address uniToken0;
        address uniToken1;
        uint128 liquidity;
        uint256 amount0Now;
        uint256 amount1Now;
        int24 tickLower;
        int24 tickUpper;
        int24 currentTick;
        uint160 sqrtPriceX96;
        // Aave (vault)
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

    // =========================================================
    //                       AAVE VIEW
    // =========================================================

    // ----------------- 1) User → vault mapping -----------------

    /// @notice Resolve the vault(UserAccount) for a given user.
    /// @dev    Returns address(0) when the user has no vault yet.
    function getUserVault(address user) public view returns (address vault) {
        vault = ACCOUNT_FACTORY.accountOf(user);
    }

    // ----------------- 2) User Aave overview -----------------

    /// @notice High-level Aave overview for a user (via their vault).
    /// @dev    Intended for "top summary card" usage on the dashboard.

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

    // ----------------- 3) Reserve metadata (global) -----------------

    /// @notice Static configuration and caps for every Aave reserve.
    /// @dev    Used to render "supported assets list" (LTV, caps, pause status, etc.).
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

    /// @dev Composes `ReserveStaticData` from the three lower-level views to avoid stack-too-deep issues.
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

    /// @dev Wraps `getReserveConfigurationData` into a smaller struct for local usage.
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

    /// @dev Wraps `getReserveTokensAddresses`.
    function _getReserveTokensData(
        address asset
    ) internal view returns (ReserveTokensView memory t) {
        (t.aToken, t.stableDebtToken, t.variableDebtToken) = AAVE_DATA_PROVIDER
            .getReserveTokensAddresses(asset);
    }

    /// @dev Wraps `getReserveCaps` and optionally `getPaused` (older deployments may not implement `getPaused`).
    function _getReserveCapsData(
        address asset
    ) internal view returns (ReserveCapsView memory caps) {
        (caps.borrowCap, caps.supplyCap) = AAVE_DATA_PROVIDER.getReserveCaps(
            asset
        );

        // Some deployments do not expose `getPaused`; fallback to `false` in that case.
        try AAVE_DATA_PROVIDER.getPaused(asset) returns (bool isPaused) {
            caps.paused = isPaused;
        } catch {
            caps.paused = false;
        }
    }

    // ----------------- 4) User reserve positions (selected assets) -----------------

    /// @notice Aave balances for a given user and a list of assets.
    /// @dev    Intended for "per-asset table" views (aToken / stable / variable debt).
    function getUserReservePositions(
        address user,
        address[] memory assets
    ) public view returns (UserReservePosition[] memory positions) {
        address vault = ACCOUNT_FACTORY.accountOf(user);
        positions = new UserReservePosition[](assets.length);

        // If the user has no vault yet, we simply return zeroed positions for the requested assets.
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

    // ----------------- 5) User reserve positions (all reserves) -----------------

    /// @notice Aave positions for a user across all reserves currently listed.
    /// @dev    Used for "show all my Aave positions" style views.
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

    // ----------------- 6) Reserve rates (APY) -----------------

    /// @notice Rate data for a single reserve (in ray).
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
        ) = AAVE_DATA_PROVIDER.getReserveData(asset);

        // For a single asset, we can safely fetch the symbol from ERC20 metadata.
        string memory symbol = IERC20Metadata(asset).symbol();

        r = ReserveRateData({
            asset: asset,
            symbol: symbol,
            liquidityRateRay: liquidityRate,
            variableBorrowRateRay: variableBorrowRate,
            stableBorrowRateRay: stableBorrowRate
        });
    }

    /// @notice Rate data for all reserves.
    function getAllReserveRates()
        external
        view
        returns (ReserveRateData[] memory rates)
    {
        IAaveProtocolDataProvider.TokenData[] memory tokens = AAVE_DATA_PROVIDER
            .getAllReservesTokens();

        uint256 len = tokens.length;
        rates = new ReserveRateData[](len);

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
            ) = AAVE_DATA_PROVIDER.getReserveData(asset);

            rates[i].asset = asset;
            rates[i].symbol = tokens[i].symbol;
            rates[i].liquidityRateRay = liquidityRate;
            rates[i].variableBorrowRateRay = variableBorrowRate;
            rates[i].stableBorrowRateRay = stableBorrowRate;
        }
    }

    // ----------------- 7) Aave oracle prices -----------------

    /// @notice Price of a single asset in Aave's base currency.
    function getAssetPrice(address asset) external view returns (uint256) {
        return AAVE_ORACLE.getAssetPrice(asset);
    }

    /// @notice Prices of multiple assets in Aave's base currency.
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

    /// @notice Base currency and its unit used by the Aave oracle.
    /// @dev    Needed by the front-end to scale prices into human-readable units.
    function getOracleBaseCurrency()
        external
        view
        returns (address baseCurrency, uint256 baseUnit)
    {
        baseCurrency = AAVE_ORACLE.BASE_CURRENCY();
        baseUnit = AAVE_ORACLE.BASE_CURRENCY_UNIT();
    }

    // =========================================================
    //                     UNISWAP V4 VIEW
    // =========================================================

    /// @notice Uniswap v4 position view for a given user and tokenId.
    /// @dev    Shape is optimized for rendering a single position card.
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
    //                 INTEGRATED STRATEGY VIEW
    // =========================================================

    /// @notice Returns a full strategy position view for a single tokenId.
    /// @dev    Ideal for a "strategy detail" panel: router meta + Uni v4 + Aave in one call.
    function getStrategyPositionView(
        uint256 tokenId
    ) external view returns (StrategyPositionView memory v) {
        // 1) Router metadata
        RouterPositionCore memory core;
        (
            core.owner,
            core.vault,
            core.supplyAsset,
            core.borrowAsset,
            core.isOpen
        ) = STRATEGY_ROUTER.positions(tokenId);

        v.core = core;

        // If there is no vault yet, return the core and zero everything else.
        if (core.vault == address(0)) {
            return v;
        }

        // 2) Uniswap v4 position snapshot
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

        // 3) Aave account state (vault as account)
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
