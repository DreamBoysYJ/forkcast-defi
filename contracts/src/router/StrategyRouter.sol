// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AaveModule} from "./AaveModule.sol";
import {UniswapV4Module} from "./UniswapV4Module.sol";
import {UserAccount} from "../accounts/UserAccount.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";

import {IERC20, IERC20Metadata} from "../interfaces/IERC20.sol";

import {UniswapV4LiquidityPreview} from "../libs/UniswapV4LiquidityPreview.sol";

/// @notice Orchestrates the full one-shot strategy:
///         wallet ERC20 -> Aave supply -> Aave borrow -> Uniswap v4 LP,
///         and the reverse (LP unwind -> repay -> withdraw).
/// @dev    High-level router that delegates protocol details to:
///         - AaveModule      : risk / caps / HF checks + vault-level IO
///         - UniswapV4Module : pool config, swaps, LP mint/burn, fee collection
contract StrategyRouter is AaveModule, UniswapV4Module {
    /// @dev Minimal position state the app actually needs to reason about.
    ///      The real financial state lives in:
    ///        - Aave (collateral / debt)
    ///        - Uniswap v4 (liquidity, fees, price)
    ///      This struct ties all of that to a single LP tokenId.
    struct PositionInfo {
        address owner;
        address vault;
        address supplyAsset;
        address borrowAsset;
        bool isOpen;
    }

    error PositionNotOpen();
    error NotPositionOwner();

    /// @dev Uniswap v4 LP tokenId → position metadata.
    mapping(uint256 => PositionInfo) public positions; // key = LP tokenId

    /// @dev Convenience index for frontends / history views.
    mapping(address => uint256[]) public userPositionIds;

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

    /// @notice Emitted after a full unwind:
    ///         - Aave debt fully repaid
    ///         - collateral withdrawn
    ///         - residual borrowAsset (PnL) handed back to the user.
    event PositionClosed(
        address indexed user,
        address indexed vault,
        uint256 indexed tokenId,
        address supplyAsset,
        address borrowAsset,
        uint256 amountSupplyReturned,
        uint256 amountBorrowReturned
    );

    /// @notice Emitted when Uniswap v4 fees are harvested without touching principal.
    event FeesCollected(
        address indexed user,
        uint256 indexed tokenId,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    );

    /// @param addressesProvider Aave V3 PoolAddressesProvider (network-level entrypoint)
    /// @param dataProvider      Aave DataProvider used for caps/config/rates
    /// @param _factory          Factory that lazily creates per-user UserAccount vaults
    /// @param _swapRouter       Mini v4 swap router used for single-pool swaps
    /// @param _positionManager  Uniswap v4 PositionManager used for LP mint/burn
    /// @param _permit2          Permit2 contract that bridges router → PoolManager allowances
    constructor(
        address addressesProvider,
        address _factory,
        address dataProvider,
        address _swapRouter,
        address _positionManager,
        address _permit2
    )
        AaveModule(addressesProvider, _factory, dataProvider)
        UniswapV4Module(_swapRouter, _positionManager)
    {
        // We intentionally keep Permit2 wiring explicit in the router,
        // since it’s the component that actually holds user-facing balances.
        permit2 = IPermit2(_permit2);
    }

    /// @notice Rich, *read-only* snapshot of a Uniswap v4 position, focused on
    ///         “what does this look like right now?” for the frontend:
    ///         - token0 / token1
    ///         - current liquidity
    ///         - full-withdrawal token amounts
    ///         - configured tick range
    ///         - current pool tick & sqrtPrice.
    function previewUniPosition(
        uint256 tokenId
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint128 liquidity,
            uint256 amount0Now,
            uint256 amount1Now,
            int24 tickLower,
            int24 tickUpper,
            int24 currentTick,
            uint160 sqrtPriceX96
        )
    {
        (
            ,
            /*PoolKey key*/ token0,
            token1,
            amount0Now,
            amount1Now
        ) = _previewLpWithdrawAmounts(tokenId);

        liquidity = positionManager.getPositionLiquidity(tokenId);

        (tickLower, tickUpper) = _getDefaultTickRange();

        IPoolManager manager = swapRouter.poolManager();
        (sqrtPriceX96, currentTick, , ) = StateLibrary.getSlot0(
            manager,
            _uniPoolId
        );
    }

    /// @dev One-time admin wiring for a pre-existing v4 pool on the network.
    ///      This does *not* initialize the pool; it just records:
    ///         - which pool we target
    ///         - which tick range we will always use for LP positions.
    function setUniswapV4PoolConfig(
        PoolKey memory key,
        int24 defaultTickLower,
        int24 defaultTickUpper
    ) external onlyAdmin {
        _setUniswapV4PoolConfig(key, defaultTickLower, defaultTickUpper);
    }

    /// @notice Main entrypoint for users:
    ///         - takes supplyAsset from the caller
    ///         - supplies into Aave
    ///         - borrows borrowAsset (HF-constrained)
    ///         - swaps into pool composition
    ///         - mints a Uniswap v4 LP position owned by the vault.
    ///
    /// @dev Caller must:
    ///        - hold `supplyAsset`
    ///        - approve this router for at least `supplyAmount`.
    function openPosition(
        address supplyAsset,
        uint256 supplyAmount,
        address borrowAsset,
        uint256 targetHF1e18 // if 0 -> 1.35e18 default
    ) external {
        // 1) Aave leg: create/update vault, supply collateral, and borrow.
        (address userAccount, uint256 borrowedAmount) = _openAavePosition(
            msg.sender,
            supplyAsset,
            supplyAmount,
            borrowAsset,
            targetHF1e18
        );

        if (borrowedAmount == 0) {
            revert BorrowAmountZero();
        }

        // Allow Uniswap contracts to pull from the vault on behalf of the router.

        UserAccount(userAccount).approveUniswapV4Operator(
            address(positionManager),
            address(this)
        );

        // 2) Uniswap v4 leg:
        //    At this point the router holds `borrowedAmount` of `borrowAsset`.
        //    We:
        //      - split & swap into pool composition
        //      - mint an LP position whose owner is the vault.
        (
            uint256 tokenId,
            uint256 spent0,
            uint256 spent1,
            uint256 amount0ForLp,
            uint256 amount1ForLp
        ) = _enterUniswapV4Position(userAccount, borrowAsset, borrowedAmount);

        // 3) Clean up any residual router balances:
        //    - leftover supplyAsset   → back to the user
        //    - leftover borrowAsset   → back to the vault then immediately repaid
        //      (keeps all Aave economics scoped to the vault).
        uint256 leftover0 = IERC20(supplyAsset).balanceOf(address(this));
        uint256 leftover1 = IERC20(borrowAsset).balanceOf(address(this));

        if (leftover0 > 0) {
            IERC20(supplyAsset).transfer(msg.sender, leftover0);
        }

        if (leftover1 > 0) {
            IERC20(borrowAsset).transfer(userAccount, leftover1);
            UserAccount(userAccount).repay(borrowAsset, leftover1);
        }

        // 4) Persist a minimal, app-level view of the position.
        userPositionIds[msg.sender].push(tokenId);

        positions[tokenId] = PositionInfo({
            owner: msg.sender,
            vault: userAccount,
            supplyAsset: supplyAsset,
            borrowAsset: borrowAsset,
            isOpen: true
        });

        emit PositionOpened(
            msg.sender,
            userAccount,
            supplyAsset,
            supplyAmount,
            borrowAsset,
            borrowedAmount,
            tokenId,
            amount0ForLp,
            amount1ForLp,
            spent0,
            spent1
        );
    }

    /// @notice Full unwind of a live position:
    ///         - remove Uniswap v4 liquidity
    ///         - consolidate into borrowAsset
    ///         - repay Aave debt
    ///         - withdraw collateral and any remaining borrowAsset to the user.
    function closePosition(uint256 tokenId) external {
        // 0) Basic ownership / lifecycle checks at the app layer.
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();
        if (p.owner != msg.sender) revert NotPositionOwner();

        address positionOwner = p.owner;
        address vault = p.vault;
        address supplyAsset = p.supplyAsset;
        address borrowAsset = p.borrowAsset;

        // 1) Uniswap v4 leg:
        //    Remove LP entirely and swap the non-borrowAsset side into borrowAsset,
        //    so that the router holds a single-asset balance to repay Aave with.
        uint256 borrowAmountOut = _exitUniswapV4PositionAndSwapToBorrow(
            vault,
            borrowAsset,
            tokenId
        );

        // 2) Aave leg:
        //    - repay all variable debt in `borrowAsset`
        //    - withdraw full collateral in `supplyAsset`
        //    - send any leftover borrowAsset (profit) back to the user.

        (
            uint256 repaidToken,
            uint256 collateralOut,
            uint256 leftoverBorrow
        ) = _closeAavePosition(
                positionOwner,
                vault,
                supplyAsset,
                borrowAsset,
                borrowAmountOut
            );

        // We do not currently expose `repaidToken` externally,
        // but keeping it in the signature makes accounting auditable on-chain.

        // 3) Mark position as closed; the on-chain protocols still hold state,
        //    but from the app perspective this position should no longer be mutated.
        p.isOpen = false;

        // 4) Emit event
        emit PositionClosed(
            positionOwner,
            vault,
            tokenId,
            supplyAsset,
            borrowAsset,
            collateralOut,
            leftoverBorrow
        );
    }

    /// @notice Convenience view:
    ///         “If I nuke this LP right now, how many token0 / token1 do I get?”
    /// @dev    Thin wrapper that hides PoolKey and only returns what UIs care about.
    function previewLpWithdrawAmounts(
        uint256 tokenId
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1
        )
    {
        (
            PoolKey memory key,
            address t0,
            address t1,
            uint256 a0,
            uint256 a1
        ) = _previewLpWithdrawAmounts(tokenId);

        token0 = t0;
        token1 = t1;
        amount0 = a0;
        amount1 = a1;
    }

    /// @notice High-level “what if I close now?” simulator:
    ///         - previews LP full-withdraw token amounts
    ///         - reads current Aave debt
    ///         - suggests a [min, max] additional borrowAsset amount the user
    ///           should prepare in the wallet to guarantee a clean repay.
    ///
    /// @dev Designed for UX:
    ///      - `minExtraFromUser`  : intuitive lower bound (shortfall after LP)
    ///      - `maxExtraFromUser`  : strict upper bound (full debt size)
    function previewClosePosition(
        uint256 tokenId
    )
        external
        view
        returns (
            address vault,
            address supplyAsset,
            address borrowAsset,
            uint256 totalDebtToken,
            uint256 lpBorrowTokenAmount,
            uint256 minExtraFromUser,
            uint256 maxExtraFromUser,
            uint256 amount1FromLp
        )
    {
        // 0) Validate we are looking at a live position, but do NOT enforce owner.
        //    Anyone can simulate; only the actual close() mutates state.
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();

        vault = p.vault;
        supplyAsset = p.supplyAsset;
        borrowAsset = p.borrowAsset;

        // 1) Simulate “LP full remove” at current price using our math helpers.
        PoolKey memory key;
        address token0;
        address token1;
        (
            key,
            token0,
            token1,
            amount0FromLp,
            amount1FromLp
        ) = _previewLpWithdrawAmounts(tokenId);

        // Map LP output to borrowAsset terms where possible.
        if (borrowAsset == token0) {
            lpBorrowTokenAmount = amount0FromLp;
        } else if (borrowAsset == token1) {
            lpBorrowTokenAmount = amount1FromLp;
        } else {
            // Misconfigured position: borrowAsset not in this pool.
            // We deliberately return a "nothing to see here" tuple instead of reverting,
            // so callers can handle this as a “non-repayable via LP” edge case.
            totalDebtToken = 0;
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        // 2) Read current variable debt in borrowAsset units directly from Aave.
        (, , address variableDebtToken) = DATA_PROVIDER
            .getReserveTokensAddresses(borrowAsset);

        if (variableDebtToken == address(0)) {
            // Defensive guard against bad pool config.
            totalDebtToken = 0;
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        totalDebtToken = IERC20(variableDebtToken).balanceOf(vault);

        // If there is no debt, the entire LP output is effectively profit.
        if (totalDebtToken == 0) {
            minExtraFromUser = 0;
            maxExtraFromUser = 0;
            return (
                vault,
                supplyAsset,
                borrowAsset,
                totalDebtToken,
                lpBorrowTokenAmount,
                minExtraFromUser,
                maxExtraFromUser,
                amount0FromLp,
                amount1FromLp
            );
        }

        // 3) Translate the “debt vs LP” relation into a user-facing range:
        //    - If LP < debt, the shortfall is what we recommend the user to top up.
        //    - If LP >= debt, user *can* close with no extra, so minExtra=0.
        if (totalDebtToken > lpBorrowTokenAmount) {
            minExtraFromUser = totalDebtToken - lpBorrowTokenAmount;
        } else {
            // In all cases, the hard upper bound is simply “the current debt size”.
            minExtraFromUser = 0;
        }

        maxExtraFromUser = totalDebtToken;
    }

    /// @notice Pulls Uniswap v4 fees for a given tokenId and sends them to the caller
    ///         without touching principal (liquidity amount stays the same).
    function collectFees(
        uint256 tokenId
    ) external returns (uint256 collected0, uint256 collected1) {
        // 1) Enforce that:
        //      - the position is live
        //      - the caller is the logical owner (vault owner), not necessarily the LP owner.
        PositionInfo storage p = positions[tokenId];
        if (!p.isOpen) revert PositionNotOpen();
        if (p.owner != msg.sender) revert NotPositionOwner();

        PoolKey memory key = _getPoolKey();

        // 2) Route protocol-level fee collection through the Uniswap module
        //    and send proceeds directly to the user wallet.
        (collected0, collected1) = _collectFees(
            key,
            p.vault,
            tokenId,
            msg.sender
        );

        emit FeesCollected(
            msg.sender,
            tokenId,
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            collected0,
            collected1
        );
    }

    /// @notice Bootstraps Permit2 allowances so the router can participate in v4
    ///         flows without spamming ERC20 approvals to PoolManager directly.
    ///
    /// @dev Intended to be called once per deployment (or per token pair change):
    ///      - Router → Permit2 (max)
    ///      - Permit2 → PoolManager (max, per token)
    function initPermit2(
        address token0,
        address token1,
        address poolManager
    ) external onlyAdmin {
        // 1) Grant Permit2 full allowance from the router for both tokens.
        IERC20(token0).approve(address(permit2), type(uint256).max);
        IERC20(token1).approve(address(permit2), type(uint256).max);

        // 2) Inside Permit2, delegate standing allowances to the PoolManager.
        //    This keeps the approvals surface tightly scoped to a single spender.
        permit2.approve(
            token0,
            poolManager,
            type(uint160).max,
            type(uint48).max
        );
        permit2.approve(
            token1,
            poolManager,
            type(uint160).max,
            type(uint48).max
        );
    }
}
