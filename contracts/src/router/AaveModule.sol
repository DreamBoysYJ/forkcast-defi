// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {UserAccount} from "../accounts/UserAccount.sol";
import {AccountFactory} from "../factory/AccountFactory.sol";
import {
    IAaveProtocolDataProvider
} from "../interfaces/aave-v3/IAaveProtocolDataProvider.sol";
import {
    IPoolAddressesProvider
} from "../interfaces/aave-v3/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "../interfaces/aave-v3/IPriceOracleGetter.sol";
import {IERC20Metadata} from "../interfaces/IERC20.sol";

/// @title AaveModule
/// @notice Shared Aave logic (sizing, guards, open/close flows) to be inherited by higher-level routers.
abstract contract AaveModule {
    // ── Core configuration shared with StrategyRouter ──
    address public admin;
    IPoolAddressesProvider public immutable PROVIDER;
    AccountFactory public immutable factory;
    IAaveProtocolDataProvider public immutable DATA_PROVIDER;
    IPriceOracleGetter public immutable ORACLE;

    /// @notice Global safety buffer for borrowing, in basis points (1e4).
    /// @dev    10000 = no extra buffer, 9000 = 90% of HF-based capacity, etc.
    uint16 public safe_borrow_bps = 10000;

    /// @notice Detailed quote used to explain / debug borrow sizing decisions.
    struct BorrowQuote {
        uint256 byHFToken;
        uint256 policyCappedToken;
        uint256 capRemainingToken;
        uint256 poolLiquidityToken;
        uint256 finalToken;
        uint256 projectedHF1e18;
    }

    // ── Errors & events reused by StrategyRouter ──

    error ZeroAddress();
    error ZeroAmount();
    error TransferFromFailed();
    error TransferFailed();
    error BorrowingDisabled();
    error BorrowCapExceeded();
    error BorrowAmountZero();
    error InsufficientLiquidity();
    error ZeroBorrowAfterSafety();
    error OraclePriceZero();
    error NotAdmin();
    error SameAddress();
    error InvalidBps();
    error SameValue();
    error SupplyingDisabled();
    error NotEnoughToRepay();

    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event SafeBorrowBpsUpdated(
        uint16 previousBps,
        uint16 newBps,
        address indexed caller
    );

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @param addressesProvider Aave V3 PoolAddressesProvider (e.g. Sepolia deployment)
    /// @param dataProvider      AaveProtocolDataProvider for reading reserve state
    /// @param _factory          AccountFactory used to resolve/create UserAccount vaults
    constructor(
        address addressesProvider,
        address _factory,
        address dataProvider
    ) {
        if (addressesProvider == address(0)) revert ZeroAddress();
        if (_factory == address(0)) revert ZeroAddress();
        if (dataProvider == address(0)) revert ZeroAddress();

        PROVIDER = IPoolAddressesProvider(addressesProvider);
        DATA_PROVIDER = IAaveProtocolDataProvider(dataProvider);
        ORACLE = IPriceOracleGetter(PROVIDER.getPriceOracle());
        admin = msg.sender;
        factory = AccountFactory(_factory);
    }

    // ── Aave helpers ──

    /// @dev Convenience accessor for the current Aave pool implementation.
    function _pool() internal view returns (IPool) {
        return IPool(PROVIDER.getPool());
    }

    /// @dev Soft check for "paused" reserves.
    /// @notice Uses a low-level call so it also works on deployments without `getPaused`.
    function _isReservePaused(address asset) internal view returns (bool) {
        (bool ok, bytes memory out) = address(DATA_PROVIDER).staticcall(
            abi.encodeWithSignature("getPaused(address)", asset)
        );
        if (ok && out.length >= 32) {
            return abi.decode(out, (bool));
        }
        return false;
    }

    /// @dev Computes borrow capacity under current account state + policy.
    /// @param borrowAsset        Asset to borrow.
    /// @param decBorrow          Decimals of `borrowAsset`.
    /// @param priceBorrow        Oracle price of `borrowAsset` in Aave base currency.
    /// @param collateralBase     Current total collateral (base units).
    /// @param effectiveLTBps     Effective liquidation threshold in bps (weighted).
    /// @param debtBaseBefore     Current total debt (base units).
    /// @param targetHF1e18       Target HF (1e18 precision); higher = safer.
    function _quoteBorrowAmount(
        address borrowAsset,
        uint8 decBorrow,
        uint256 priceBorrow,
        uint256 collateralBase,
        uint256 effectiveLTBps,
        uint256 debtBaseBefore,
        uint256 targetHF1e18
    ) internal view returns (BorrowQuote memory Q) {
        if (priceBorrow == 0 || targetHF1e18 == 0) {
            return Q;
        }

        // 1) Compute HF-constrained additional debt capacity in base units.
        uint256 capacityBase = (collateralBase * effectiveLTBps * 1e18) /
            (10000 * targetHF1e18);
        uint256 byHFBase = capacityBase > debtBaseBefore
            ? (capacityBase - debtBaseBefore)
            : 0;

        // 2) Convert base capacity → token units.
        uint256 scaleBorrow = 10 ** uint256(decBorrow);
        Q.byHFToken = (byHFBase == 0)
            ? 0
            : (byHFBase * scaleBorrow) / priceBorrow;

        // 3) Apply module-level safety buffer (safe_borrow_bps).
        Q.policyCappedToken = (Q.byHFToken * uint256(safe_borrow_bps)) / 10_000;

        // 4) Enforce borrowCap and on-chain liquidity constraints.
        (uint256 borrowCap, ) = DATA_PROVIDER.getReserveCaps(borrowAsset);
        (address aToken, address sDebt, address vDebt) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        uint256 totalDebtToken = 0;
        if (sDebt != address(0)) totalDebtToken += IERC20(sDebt).totalSupply();
        if (vDebt != address(0)) totalDebtToken += IERC20(vDebt).totalSupply();

        // Remaining protocol capacity under borrowCap (if any).
        if (borrowCap == 0) {
            Q.capRemainingToken = type(uint256).max;
        } else {
            uint256 capMaxToken = borrowCap * scaleBorrow;
            Q.capRemainingToken = capMaxToken > totalDebtToken
                ? (capMaxToken - totalDebtToken)
                : 0;
        }

        // Available liquidity held by the aToken (reserve cash).
        Q.poolLiquidityToken = (aToken == address(0))
            ? 0
            : IERC20(borrowAsset).balanceOf(aToken);

        // 5) Final borrow size is the min across policy, caps, and liquidity.
        Q.finalToken = Q.policyCappedToken;
        if (Q.finalToken > Q.capRemainingToken)
            Q.finalToken = Q.capRemainingToken;
        if (Q.finalToken > Q.poolLiquidityToken)
            Q.finalToken = Q.poolLiquidityToken;

        // 6) Project HF after borrowing Q.finalToken.
        if (Q.finalToken == 0) {
            Q.projectedHF1e18 = 0;
        } else {
            uint256 finalBase = (Q.finalToken * priceBorrow) / scaleBorrow;
            uint256 projectedDebtBase = debtBaseBefore + finalBase;
            Q.projectedHF1e18 = (projectedDebtBase == 0)
                ? type(uint256).max
                : (collateralBase * effectiveLTBps * 1e18) /
                    (10000 * projectedDebtBase);
        }
    }

    /// @dev Returns true if the reserve is currently borrowable under Aave config + pause flags.
    function _aaveCanBorrow(address asset) internal view returns (bool) {
        if (asset == address(0)) revert ZeroAddress();

        (
            ,
            ,
            ,
            ,
            ,
            ,
            bool borrowingEnabled,
            ,
            bool isActiveBorrow,
            bool isFrozenBorrow
        ) = DATA_PROVIDER.getReserveConfigurationData(asset);

        return
            borrowingEnabled &&
            isActiveBorrow &&
            !isFrozenBorrow &&
            !_isReservePaused(asset);
    }

    /// @dev Returns true if the reserve is currently acceptable as collateral and active.
    function _aaveCanSupply(address asset) internal view returns (bool) {
        if (asset == address(0)) revert ZeroAddress();

        (
            ,
            ,
            ,
            ,
            ,
            bool usageAsCollateralEnabled,
            ,
            ,
            bool isActive,
            bool isFrozen
        ) = DATA_PROVIDER.getReserveConfigurationData(asset);

        return
            isActive &&
            !isFrozen &&
            usageAsCollateralEnabled &&
            !_isReservePaused(asset);
    }

    // ── Admin controls ──

    /// @notice Updates the module admin.
    function changeAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        if (newAdmin == admin) revert SameAddress();
        address prev = admin;
        admin = newAdmin;
        emit AdminChanged(prev, newAdmin);
    }

    /// @notice Adjusts the global safety factor applied on top of HF-based borrow size.
    function setSafeBorrowBfs(uint16 newBps) external onlyAdmin {
        if (newBps > 10000) revert InvalidBps();
        if (newBps == safe_borrow_bps) revert SameValue();

        uint16 prev = safe_borrow_bps;
        safe_borrow_bps = newBps;
        emit SafeBorrowBpsUpdated(prev, newBps, msg.sender);
    }

    // ── previewBorrow: shared quote logic used by the router ──

    /// @notice Simulates supply + borrow to show the user expected borrow size and HF.
    /// @dev    Intended for front-end previews; does not mutate state.
    function previewBorrow(
        address user,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18
    )
        external
        view
        returns (
            uint256 finalToken,
            uint256 projectedHF1e18,
            uint256 byHFToken,
            uint256 policyMaxToken,
            uint256 capRemainingToken,
            uint256 liquidityToken,
            uint256 collBeforeBase,
            uint256 debtBeforeBase,
            uint256 collAfterBase,
            uint256 ltBeforeBps,
            uint256 ltAfterBps
        )
    {
        // 0) Default target HF if not provided (acts as a "safety profile").
        if (targetHF1e18 == 0) {
            targetHF1e18 = 135e16;
        }
        if (supplyAmount == 0) revert ZeroAmount();

        // 1) Read current vault account data if it exists.
        address vault = factory.accountOf(user);
        if (vault != address(0)) {
            (collBeforeBase, debtBeforeBase, , ltBeforeBps, , ) = _pool()
                .getUserAccountData(vault);
        } else {
            // First-time user: treat as empty account.
            collBeforeBase = 0;
            debtBeforeBase = 0;
            ltBeforeBps = 0;
        }

        // 2) Early exit if this asset is not currently acceptable as collateral.
        if (!_aaveCanSupply(supplyAsset)) {
            return (
                0,
                0,
                0,
                0,
                0,
                0,
                collBeforeBase,
                debtBeforeBase,
                collBeforeBase,
                ltBeforeBps,
                ltBeforeBps
            );
        }

        // 3) Pull oracle prices and decimals.
        uint8 decSupply = IERC20Metadata(supplyAsset).decimals();
        uint8 decBorrow = IERC20Metadata(borrowAsset).decimals();

        uint256 priceSupply = ORACLE.getAssetPrice(supplyAsset);
        uint256 priceBorrow = ORACLE.getAssetPrice(borrowAsset);
        if (priceSupply == 0 || priceBorrow == 0) {
            // If either price is zero, treat as non-borrowable in preview.
            return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        // 4) Simulate adding the new supply and recompute effective LT.
        uint256 scaleSupply = 10 ** uint256(decSupply);
        uint256 supplyValueBase = (supplyAmount * priceSupply) / scaleSupply;
        collAfterBase = collBeforeBase + supplyValueBase;

        (, , uint256 ltSupplyBps, , , , , , , ) = DATA_PROVIDER
            .getReserveConfigurationData(supplyAsset);
        if (collAfterBase == 0) {
            ltAfterBps = 0;
        } else if (collBeforeBase == 0) {
            ltAfterBps = ltSupplyBps;
        } else {
            ltAfterBps =
                (collBeforeBase * ltBeforeBps + supplyValueBase * ltSupplyBps) /
                collAfterBase;
        }

        // 5) Early exit if borrowing is disabled or unsafe for this asset.
        if (!_aaveCanBorrow(borrowAsset)) {
            return (
                0,
                0,
                0,
                0,
                0,
                0,
                collBeforeBase,
                debtBeforeBase,
                collAfterBase,
                ltBeforeBps,
                ltAfterBps
            );
        }

        // 6) Use shared borrow sizing logic.
        BorrowQuote memory Q = _quoteBorrowAmount(
            borrowAsset,
            decBorrow,
            priceBorrow,
            collAfterBase, // collateralBase
            ltAfterBps, // effectiveLTBps
            debtBeforeBase, // debtBaseBefore
            targetHF1e18
        );

        // 7) Map quote fields to the return tuple.
        byHFToken = Q.byHFToken;
        policyMaxToken = Q.policyCappedToken;
        capRemainingToken = Q.capRemainingToken;
        liquidityToken = Q.poolLiquidityToken;
        finalToken = Q.finalToken;
        projectedHF1e18 = Q.projectedHF1e18;
    }

    /// @dev Core "open Aave position" flow:
    ///      - transfer collateral from user to vault via router
    ///      - supply to Aave
    ///      - size and execute borrow
    ///      - pull borrowed tokens back into the router as operator
    function _openAavePosition(
        address user,
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18 // if 0, defaults to 1.35e18
    ) internal returns (address userAccount, uint256 borrowedAmount) {
        if (supplyAsset == address(0)) revert ZeroAddress();
        if (borrowAsset == address(0)) revert ZeroAddress();
        if (supplyAmount == 0) revert ZeroAmount();
        if (targetHF1e18 == 0) targetHF1e18 = 135e16; // 1.35e18

        userAccount = factory.getOrCreate(user);

        // Check that the collateral asset is supplyable right now.
        if (!_aaveCanSupply(supplyAsset)) {
            revert SupplyingDisabled();
        }

        // Pull collateral from user → router (user must have approved `supplyAsset`).
        if (
            !IERC20(supplyAsset).transferFrom(user, address(this), supplyAmount)
        ) {
            revert TransferFromFailed();
        }

        // Forward collateral from router → vault.
        if (!IERC20(supplyAsset).transfer(userAccount, supplyAmount)) {
            revert TransferFailed();
        }

        // Vault supplies collateral into Aave.
        UserAccount(userAccount).supply(supplyAsset, supplyAmount);

        // ---- Borrow sizing with HF-first policy ----

        // Early validation for the borrow asset (paused/frozen/disabled).
        if (!_aaveCanBorrow(borrowAsset)) {
            revert BorrowingDisabled();
        }

        // Fresh account data after the supply above.
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            uint256 currentLiquidationThreshold, // BPS (1e4)
            ,

        ) = _pool().getUserAccountData(userAccount);

        // Token decimals and oracle price for the borrow asset.
        uint8 decBorrow = IERC20Metadata(borrowAsset).decimals();
        uint256 priceBorrow = ORACLE.getAssetPrice(borrowAsset);
        if (priceBorrow == 0) revert OraclePriceZero();

        // Compute safe borrow size under HF, caps, and liquidity.
        BorrowQuote memory Q = _quoteBorrowAmount(
            borrowAsset,
            decBorrow,
            priceBorrow,
            totalCollateralBase, // collateralBase (supply 반영됨)
            currentLiquidationThreshold, // effectiveLTBps
            totalDebtBase, // debtBaseBefore
            targetHF1e18
        );

        // Validate reason for refusal if borrow ends up zero.
        if (Q.capRemainingToken == 0) revert BorrowCapExceeded();
        if (Q.poolLiquidityToken == 0) revert InsufficientLiquidity();
        if (Q.finalToken == 0) revert ZeroBorrowAfterSafety();

        // Execute borrow via the vault.
        UserAccount(userAccount).borrow(borrowAsset, Q.finalToken);

        // Pull borrowed tokens from vault → router, so router can route into LP, swaps, etc.
        UserAccount(userAccount).pullToOperator(borrowAsset, Q.finalToken);

        borrowedAmount = Q.finalToken;
    }

    /// @dev Closes the Aave leg:
    ///      - repay debt using router-held `borrowAsset` (including LP proceeds + leftovers)
    ///      - withdraw all collateral back to the user
    ///      - forward any excess `borrowAsset` (profit/leftovers) to the user
    /// @param user            Position owner (expected caller at router level).
    /// @param vault           UserAccount (vault) address.
    /// @param supplyAsset     Collateral asset previously supplied to Aave.
    /// @param borrowAsset     Debt asset borrowed from Aave.
    /// @param borrowAmountOut Expected amount of `borrowAsset` router got from LP close.
    function _closeAavePosition(
        address user,
        address vault,
        address supplyAsset,
        address borrowAsset,
        uint256 borrowAmountOut
    )
        internal
        returns (
            uint256 actualRepaid,
            uint256 collateralOut,
            uint256 leftovevrBorrow
        )
    {
        if (vault == address(0)) revert ZeroAddress();
        if (supplyAsset == address(0)) revert ZeroAddress();
        if (borrowAsset == address(0)) revert ZeroAddress();

        // 0) Router's current `borrowAsset` balance (from LP + potential leftovers).
        uint256 routerBal = IERC20(borrowAsset).balanceOf(address(this));
        if (routerBal == 0 && borrowAmountOut == 0) {
            // No proceeds from LP and no residual balance on the router.
            // At this point there is nothing to repay with, so treat as invalid close attempt.
            revert ZeroBorrowAfterSafety();
        }

        // -------- Repay Debt --------

        // 1) Compute the exact outstanding debt (principal + interest) from Aave's debt token.
        uint256 debtToken = _getExactDebtToken(vault, borrowAsset);

        uint256 collateralAmt;
        if (debtToken == 0) {
            // 이론상 여기에 올 일은 거의 없지만, 방어적 처리:
            // 빚이 없으면 담보/남은 토큰만 유저에게 돌려주는 흐름으로 가도 됨.
            // 여기서는 간단히, 담보/남은 borrowAsset만 유저에게 넘기는 쪽으로 처리.
            collateralAmt = _getExactCollateralToken(vault, supplyAsset);
            if (collateralAmt > 0) {
                collateralOut = UserAccount(vault).withdrawTo(
                    supplyAsset,
                    collateralAmt,
                    user
                );
            }

            leftovevrBorrow = IERC20(borrowAsset).balanceOf(address(this));
            if (leftovevrBorrow > 0) {
                IERC20(borrowAsset).transfer(user, leftovevrBorrow);
            }
            return (actualRepaid, collateralOut, leftovevrBorrow);
        }

        // 2) If current router balance is not enough to fully repay, pull the shortfall from the user.
        //    The user must have pre-approved `borrowAsset` to the router.
        if (routerBal < debtToken) {
            uint256 shortfall = debtToken - routerBal;

            // If this transferFrom fails, it naturally reflects that the user did not
            // provide enough funds/approval, and the close operation reverts.
            IERC20(borrowAsset).transferFrom(user, address(this), shortfall);

            routerBal += shortfall;
        }

        // 3) Router → vault for the exact debt amount, then vault repays Aave.
        IERC20(borrowAsset).transfer(vault, debtToken);
        UserAccount(vault).repay(borrowAsset, debtToken);
        actualRepaid = debtToken;

        // -------- Withdraw Collateral --------

        // 4) Withdraw the entire collateral position from the vault back to the user.
        collateralAmt = _getExactCollateralToken(vault, supplyAsset);
        if (collateralAmt > 0) {
            collateralOut = UserAccount(vault).withdrawTo(
                supplyAsset,
                collateralAmt,
                user
            );
        }

        // -------- Collect fees / profit --------

        // 5) Any `borrowAsset` left on the router now represents profit / leftovers; forward to user.
        leftovevrBorrow = IERC20(borrowAsset).balanceOf(address(this));
        if (leftovevrBorrow > 0) {
            IERC20(borrowAsset).transfer(user, leftovevrBorrow);
        }
    }

    /// @dev Reads current variable debt (principal + interest) from the Aave debt token.
    function _getExactDebtToken(
        address vault,
        address borrowAsset
    ) internal view returns (uint256) {
        (, , address variableDebtTokenAddress) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        return IERC20(variableDebtTokenAddress).balanceOf(vault);
    }

    /// @dev Reads current collateral balance (principal + yield) via the aToken.
    function _getExactCollateralToken(
        address vault,
        address supplyAsset
    ) internal view returns (uint256) {
        (address aToken, , ) = DATA_PROVIDER.getReserveTokensAddresses(
            supplyAsset
        );

        return IERC20(aToken).balanceOf(vault);
    }
}
