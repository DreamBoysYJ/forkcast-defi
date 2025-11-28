# Core contracts (`src/`)

This folder contains all on-chain contracts for the **Forkcast One-Shot Strategy**:
a leverage LP strategy that routes user funds from Aave V3 to Uniswap v4 in a
single “open position” flow, and unwinds everything in a mirrored “close
position” flow.

At a high level:

- Users interact only with **StrategyRouter** (plus view-only **StrategyLens**).
- Each user gets a dedicated **UserAccount** vault that owns Aave positions and LP.
- A separate **Uniswap v4 mini router** and **hook** contracts handle swaps and
  price logging.
- The system is intentionally demo-friendly: a single collateral asset, a
  single borrow asset, and a single Uniswap v4 pool configuration.

> This README is meant for reviewers who want to understand the architecture
> and how the pieces fit together before reading individual contracts.

---

## 1. Module overview

### `accounts/`

- **`UserAccount.sol`**  
  Per-user vault contract.
  - Holds the user’s Aave collateral / debt position and any LP tokens.
  - Only the owner and the `StrategyRouter` (operator) can trigger actions.
  - Exposes minimal methods for:
    - Supplying collateral to Aave
    - Borrowing against that collateral
    - Repaying and withdrawing

### `factory/`

- **`AccountFactory.sol`**  
  Factory responsible for lazy-creating `UserAccount` vaults.
  - Deterministic mapping `user → vault`.
  - Ensures each EOA gets at most one vault instance.
  - Used by the router at `openPosition` time (and by front-end for lookups).

### `hook/`

- **`HookFactory.sol`**  
  Creates Uniswap v4 hooks with deterministic addresses (used together with `HookMiner` in scripts).

- **`SwapPriceLoggerHook.sol`**  
  Lightweight Uniswap v4 hook:
  - Registers only the `AFTER_SWAP` flag.
  - Emits events with tick and sqrtPrice so the UI can display price / swap history.
  - No stateful logic that can grief the pool.

### `lens/`

- **`StrategyLens.sol`**  
  Read-only view contract for building the dashboard.
  - Aggregates data from:
    - Aave pool + data provider + oracle
    - UserAccount vaults
    - StrategyRouter and Uniswap v4 pool
  - Main responsibilities:
    - Aave reserve and user state (supplies, borrows, health factor, LTV…)
    - Strategy-level view (`getStrategyPositionView`) combining Aave + LP
    - Per-position Uniswap v4 overviews for the UI

### `router/`

- **`StrategyRouter.sol`**  
  Main entrypoint for users.

  Conceptually split into:

  - **Aave module**
    - Accepts ERC-20 from the user.
    - Moves funds into the user’s `UserAccount` vault.
    - Supplies collateral and optionally borrows a second asset.
    - Enforces safety policies (HF target, borrow caps, basic guards).
  - **Uniswap v4 module**
    - Uses the borrowed asset to enter a Uniswap v4 LP position.
    - LP is owned by the vault; router acts as operator.
    - Supports future extension for closing / re-entering positions.

  Core flows (high-level):

  - `openPosition(...)`
    - `factory.getOrCreate(user)` → vault
    - vault: `supply` + (optional) `borrow`
    - router: swap / LP via v4 module
  - `closePosition(...)`
    - remove LP → swap back → repay debt → withdraw collateral.
  - `collectFees(tokenId)`
  - Looks up the user’s vault that owns the Uniswap v4 LP `tokenId`.
  - Calls the v4 `PositionManager.collect` to claim only the accumulated fees.
  - Sends the collected token0 / token1 fees to the user’s wallet (msg.sender), **not** the vault.
  - Does not change LP liquidity or the user’s Aave supply/borrow position.

- **`AaveModule.sol`**  
  Internal logic extracted from `StrategyRouter` for Aave interactions.

- **`UniswapV4Module.sol`**  
  Internal logic extracted from `StrategyRouter` for Uniswap v4 interactions.

### `uniswapV4/`

- **`Miniv4SwapRouter.sol`**  
  Minimal Uniswap v4 swap router used by both:

  - The main strategy (for actual user flows),
  - And the demo-trader backend (to generate fees and event samples).

  Only implements what this project needs:

  - Simple `exactInputSingle`-style path
  - ETH/erc20 handling where necessary
  - No complex multicall or routing logic from the official Universal Router

### `interfaces/`

- A collection of minimal interfaces for:
  - ERC-20 tokens
  - Aave V3 Pool / DataProvider / Oracle
  - Uniswap v4 PoolManager / PositionManager / Permit2

> All external protocol interfaces (Aave, Uniswap v4, etc.) are vendored into
> `lib/` / `interfaces/` so the build never depends on upstream repo layout or
> ABI changes, keeping compilation deterministic and error-free.

### `libs/`

- Internal helper libraries shared across modules
  - Math / type helpers
  - Hook-related utilities
  - Any project-specific helpers that don’t warrant a full contract

### `types/`

- Shared structs and enums used by the router, lens and modules
  - Strategy position views
  - Internal config types for v4 pool settings, Aave policy parameters, etc.

### `utils/`

- Small utility contracts and libraries that don’t fit elsewhere.
- Often used in tests and scripts as well.

---

## 2. Key call flows

This section intentionally stays high-level so it doesn’t get out of date when
implementation details change. For exact signatures, see the contracts.

### 2.1. Open position (one-shot)

1. **User → StrategyRouter**: calls `openPosition(...)`.
2. **Router → AccountFactory**: `getOrCreate(user)` to ensure the user has a `UserAccount` vault.
3. **Vault → Aave**
   - supplies `supplyAsset` as collateral
   - optionally borrows `borrowAsset` up to a safe amount (HF / caps / liquidity checks).
4. **Vault ↔ Router → Uniswap v4**
   - the vault approves the router for the borrowed asset
   - the router pulls the borrowed tokens from the vault
   - the router (via the v4 module) swaps into the desired pool ratio
   - LP is added to the configured Uniswap v4 pool, with the LP position owned by the vault.
5. **StrategyLens** picks up:
   - updated Aave account data
   - LP position information (via the vault)
   - derived USD metrics (collateral, debt, HF, borrow power used, etc.)

### 2.2. Collect fees (current)

1. **User → StrategyRouter**: calls `collectFees(tokenId)` for a given Uniswap v4 LP position.
2. **Router → Vault**: determines the user’s `UserAccount` and verifies that the vault owns `tokenId`.
3. **Router → Uniswap v4**: uses the vault’s LP position to call the v4 position manager / pool
   and collect the accumulated fees for that position.
4. **Router → User**: transfers the collected token0/token1 fees out to the user’s EOA
   (not kept inside the vault), so the wallet immediately receives the rewards.
5. **StrategyLens**: on the next read, shows the updated LP balances and fee-related numbers.

### 2.3. Close position (planned / partial)

1. Remove LP from Uniswap v4 using the vault’s position (via the router / v4 module).
2. Swap the withdrawn amounts back into the debt asset as needed.
3. Repay Aave debt from the swapped funds.
4. Withdraw remaining collateral from Aave back to the user (or keep it in the vault, depending on policy).
5. Update position state in `StrategyRouter` / `UserAccount`.
6. **StrategyLens** exposes a unified “post-close” view (zero or minimal debt, updated HF, no active LP).

---

## 3. Reading order recommendation

If you’re new to the codebase, a good order is:

1. `router/StrategyRouter.sol`  
   – entrypoint and overall flow.

2. `accounts/UserAccount.sol` and `factory/AccountFactory.sol`  
   – vault model and how users are mapped to vaults.

3. `router/AaveModule.sol` and `router/UniswapV4Module.sol`  
   – concrete interactions with Aave and Uniswap v4.

4. `lens/StrategyLens.sol`  
   – how the dashboard data is composed from on-chain state.

5. `hook/SwapPriceLoggerHook.sol` + `uniswapV4/Miniv4SwapRouter.sol`  
   – how price events and LP management integrate with Uniswap v4.

---

## 4. Assumptions & limitations

- Single collateral asset and single borrow asset (for demo simplicity).
- Single Uniswap v4 pool configuration (AAVE/LINK + one hook).
- Designed for Sepolia deployment, but the pattern generalizes to mainnet
  by changing addresses and pool configuration.
- No upgradeability / proxy pattern; contracts are intentionally simple to
  audit and reason about.

---

## 5. Related folders

- `script/` – Foundry scripts for deploying and initializing all contracts
  (core, hook factory, v4 pool, router config).
- `test/` – Unit and integration tests. There is also an `old_test/` folder
  with earlier one-off tests used while evolving the design.
