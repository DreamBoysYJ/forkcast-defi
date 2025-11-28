# tests/

High-level goal: prove that every building block of the strategy (Aave, Uniswap v4, Router, Lens, Hooks) actually does what the UI promises — on a fork that is as close as possible to production.

This directory is organized by **protocol / concern**, not by file name.

---

## 1. Aave

**`aave/AaveSepoliaProbe.t.sol`**

- Forks Sepolia and talks to real Aave V3 contracts.
- Verifies we can:
  - read reserve config / caps / rates
  - read user account data (HF, LTV, collateral, debt)
- Used as a “protocol sandbox” before wiring Aave into our own contracts.

---

## 2. Lens

**`lens/StrategyLens.t.sol`**

- Unit + light integration tests for `StrategyLens`:
  - `getUserAaveOverview`
  - `getAllAaveReserves`, `getAllReserveRates`
  - user reserve positions (per-asset, all-assets)
  - Uni v4 + Aave combined `getStrategyPositionView`
- Ensures the dashboard can rely on Lens as a single source of truth without calling Router directly.

---

## 3. Uniswap v4 & Strategy

`uniswapV4/` tests are layered from “protocol probes” → “infra components” → “full strategy”.

### 3-1. Protocol probes

- **`UniswapV4Probe.t.sol`**  
  Initializes a v4 pool on a fork and checks:
  - pool state (`slot0`, ticks, liquidity)
  - add/remove liquidity flows
- **`FindHookSalt.test.sol`**  
  Utility test to brute-force / verify CREATE2 salts for hook addresses.

### 3-2. Router & hooks

- **`MiniV4SwapRouter.t.sol`**  
  Tests the minimal swap router in isolation:
  - exact-in single-pool swaps
  - unlock callback, take/sync/settle behavior
  - slippage guard (`amountOutMin`).
- **`SwapPriceLoggerHook.t.sol`**  
  Verifies:
  - hook permission bits
  - only-PoolManager access control
  - price/tick logging after swaps.

### 3-3. StrategyRouter (Aave + v4)

- **`StrategyRouter_OpenPosition.t.sol`**  
  End-to-end “enter strategy” tests:
  - user approves collateral → Router
  - Router opens Aave vault, supplies, borrows
  - Router enters a Uni v4 LP position for the vault
  - leftover tokens, stored position metadata, events are all checked.
- **`StrategyRouter_ClosePosition.t.sol`**  
  End-to-end “exit strategy” tests:
  - remove LP
  - swap back into borrow asset
  - repay Aave debt and withdraw collateral
  - remaining profit is returned to the user.

---

## 4. Testing philosophy

- Tests are written **incrementally with the contracts**, not after everything is “finished”.
- Every new behavior is introduced together with:
  1. a small unit test (local logic), and
  2. when relevant, a fork test that hits real Aave / Uni v4 contracts.
- Probe tests (`*Probe`, `FindHookSalt`) exist to de-risk protocol behavior **before** we depend on it in the main strategy.

---

## 5. How to run

- Run all tests:

  ```bash
  forge test
  ```
