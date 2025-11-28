# Forkcast DeFi – Contracts

Leveraged LP “one-shot strategy” contracts for **Forkcast DeFi**.  
Aave V3 + Uniswap v4 + per-user vaults + minimal router & hooks.

The goal:  
**One button** to go `supply → borrow → Uniswap v4 LP`,  
and one button to `close → repay debt → withdraw collateral`,  
with view helpers + fee collection.

---

## 1. Architecture Overview

On a high level:

- **UserAccount (vault)**

  - One smart-contract vault per user (created via `AccountFactory`).
  - Holds Aave collateral, Aave debt, and Uniswap v4 LP positions.
  - Only the owner (EOA) and the `StrategyRouter` (operator) can act.

- **AccountFactory**

  - Lazily deploys `UserAccount` vaults.
  - `accountOf(user)` returns the vault address (or zero if not created yet).

- **StrategyRouter**

  - Main entrypoint for users.
  - `openPosition`:
    1. Pulls `supplyAsset` from the user.
    2. Supplies to Aave V3 (via `AaveModule` / `UserAccount`).
    3. Borrows `borrowAsset` from Aave.
    4. Uses `Miniv4SwapRouter` + Uniswap v4 `PositionManager` to create an LP position.
  - `closePosition`:
    1. Removes Uniswap v4 liquidity.
    2. Swaps into `borrowAsset` as needed.
    3. Repays Aave debt.
    4. Withdraws remaining collateral back to the user.
  - `collectFees`:
    - Collects only Uniswap v4 trading fees for a given LP NFT, without changing liquidity.
  - `previewClosePosition`:
    - Off-chain friendly view helper: returns
      - Aave total debt (in `borrowAsset`),
      - How much of that can be covered by LP,
      - Min/max extra `borrowAsset` the user should prepare.

- **AaveModule**

  - Thin helper for Aave V3 interactions (supply, borrow, repay, withdraw).
  - Router delegates the actual protocol calls here.

- **Miniv4SwapRouter**

  - Minimal Uniswap v4 router focused on:
    - `exactInputSingle` swaps
    - LP creation / removal via `IPositionManager`.
  - Used by `StrategyRouter` and test helpers to interact with v4.

- **Hooks & Observability**
  - `SwapPriceLoggerHook`:
    - AFTER_SWAP hook that logs:
      - `PoolId`, current tick, `sqrtPriceX96`, timestamp.
    - Deployed with `HookMiner` to get an address that encodes the desired flags.
  - Used for:
    - Debugging price movement,
    - Emitting events the front-end can subscribe to (e.g., “price moved out of range”).

---

## 2. Repository Layout

> This is the contracts package (Foundry).

- `src/`

  - `accounts/`
    - `UserAccount.sol` – per-user Aave/LP vault.
  - `factory/`
    - `AccountFactory.sol` – creates and tracks vaults.
  - `router/`
    - `StrategyRouter.sol` – main user entrypoint (open/close/collect/preview).
    - `AaveModule.sol` – Aave V3 helper logic.
  - `uniswapV4/`
    - `Miniv4SwapRouter.sol` – minimal Uniswap v4 swap/router.
  - `hook/`
    - `SwapPriceLoggerHook.sol` – AFTER_SWAP hook for price logging.
  - `libs/`
    - `HookMiner.sol`, `Hooks.sol`, etc – utilities for Uniswap v4 hooks / CREATE2.
  - (Optional) `lens/`
    - `StrategyLens.sol` – view helpers for dashboard (Aave reserves, positions, etc.).

- `test/`

  - `UniswapV4Probe.t.sol`
    - Low-level Uniswap v4 probe tests:
      - pool init, add/remove liquidity, fee collection,
      - basic swap/revert behavior.
  - `SwapPriceLoggerHook.t.sol`
    - Tests that swaps through `Miniv4SwapRouter` trigger `SwapPriceLogged` events.
  - `StrategyRouterClosePosition.t.sol`
    - Integration-style tests on a Sepolia fork:
      - `openPosition` happy path,
      - `closePosition` happy path,
      - `collectFees` happy path & edge cases,
      - `previewClosePosition` sanity checks,
      - reverts (not owner, already closed, insufficient approve/balance, etc.).

- `script/`
  - (Optional) Deployment scripts (Foundry `forge script`).

---

## 3. Getting Started

### 3.1. Requirements

- `foundry` (forge/cast/anvil)
- Access to an Ethereum RPC (Sepolia in this project)

### 3.2. Env Variables

Create a `.env` in the repo root:

```bash
SEPOLIA_RPC_URL=<your_rpc_url>

# Aave V3 Sepolia
AAVE_POOL_ADDRESSES_PROVIDER=<address>
AAVE_PROTOCOL_DATA_PROVIDER=<address>

# Uniswap v4 Sepolia
POOL_MANAGER=<address>
POSITION_MANAGER=<address>
PERMIT2=<address>

# Underlying ERC20s used as supply/borrow assets
AAVE_UNDERLYING_SEPOLIA=<address>
LINK_UNDERLYING_SEPOLIA=<address>
WBTC_UNDERLYING_SEPOLIA=<address>

# Test EOA used in fork tests
USER_ADDRESS=<some_sepolia_eoa_with_tokens_optional>
```
