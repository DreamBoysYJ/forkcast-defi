# Forkcast DeFi – Web (Next.js)

Next.js app (frontend + lightweight backend) for the **Forkcast DeFi one-shot strategy**.

- Shows Aave V3 + Uniswap v4 + StrategyRouter positions.
- Lets a user:
  - Open a leveraged LP position (via StrategyRouter).
  - Preview & close a position.
  - Collect Uniswap v4 fees.
- Subscribes to hook events (SwapPriceLogger) and renders them in the UI.

---

## 1. Tech Stack

- **Framework**: Next.js (App Router)
- **Language**: TypeScript
- **Web3**: viem / wagmi (EVM), custom hooks
- **State**: React hooks + Zustand store (for hook events)
- **Styling**: CSS (globals + component-level), Tailwind-like layout components
- **Backend**: Next.js API routes under `src/app/api`

---

## 2. High-Level Flow

1. User connects wallet on the main dashboard.
2. Frontend reads:
   - Aave reserves / user positions,
   - Uniswap v4 LP positions,
   - StrategyRouter positions.
3. User actions:
   - `openPosition` → call StrategyRouter.
   - `previewClosePosition` → show how much will be repaid / returned.
   - `closePosition` → unwind Aave + Uniswap v4.
   - `collectFees` → only claim LP fees.
4. Hook events (`SwapPriceLogged`) are listened to and stored in a Zustand store, then shown in the “Events / Hook log” area.

---

## 3. Folder Structure

> Root is the Next.js app. Only the **src** tree is shown here.

```text
src
 ├─ abi/
 ├─ app/
 │   ├─ api/
 │   ├─ globals.css
 │   ├─ layout.tsx
 │   └─ page.tsx
 ├─ components/
 │   ├─ common/
 │   ├─ dashboard/
 │   ├─ modals/
 │   ├─ Connect.tsx
 │   └─ Providers.tsx
 ├─ config/
 │   └─ contracts.ts
 ├─ hooks/
 ├─ lib/
 │   ├─ chain.ts
 │   ├─ contracts.ts
 │   ├─ demoTrader.ts
 │   └─ store/
 │       └─ useHookEventStore.ts
```



## `src/abi/`

Contract ABIs used by viem/wagmi.  
Includes `StrategyRouter`, `StrategyLens`, `UserAccount`, etc.

---

## `src/app/`

- `layout.tsx` – root layout (providers, global wrappers)
- `page.tsx` – main dashboard page (cards, sections)
- `globals.css` – global styles
- `api/` – Next API routes (server-side helpers, e.g. demo trader / background swaps)

---

## `src/components/`

### `common/`
Reusable UI pieces:
- cards
- sections
- headers
- buttons
- layout components
- etc.

### `dashboard/`
Aave / Uniswap / Strategy panels:
- “Your Supplies”
- “Your Borrows”
- “Strategy Positions”
- “Hook Events / Price Log”

### `modals/`
Dialogs for:
- opening a position
- previewing close
- confirming close / collect
- etc.

### `Connect.tsx`
Wallet connect button + status.

### `Providers.tsx`
Wraps the app with Web3 providers (wagmi/viem), Zustand, etc.

---

## `src/config/`

### `contracts.ts`
Central place for on-chain addresses and chain IDs.

Reads from env vars like:

- `NEXT_PUBLIC_STRATEGY_ROUTER_ADDRESS`
- `NEXT_PUBLIC_STRATEGY_LENS_ADDRESS`
- `NEXT_PUBLIC_AAVE_PROTOCOL_DATA_PROVIDER`

Used by `lib/contracts.ts`.

---

## `src/hooks/`

React hooks to read/write on-chain data.

### Aave data
- `useAaveBorrowAssets`
- `useAaveSupplyAssets`
- `useAaveUserBorrows`
- `useAaveUserSupplies`

### Strategy / position
- `useStrategyPositionView`
- `useUserUniPositions`

### Actions
- `useClosePosition`
- `useCollectFees`

### Preview / UI helpers
- `usePreviewClosePosition`
- `useWalletTokenBalances`

### Events
- `useHookEventStore` (wrapper over Zustand store in `lib/store`).

> Hooks are the main UX boundary:  
> pages/components only call hooks; hooks talk to viem/wagmi + contracts and return typed data + loading/error states.

---

## `src/lib/`

### `chain.ts`
Chain configuration (Sepolia chain, RPC URL, block explorer links, etc.).

### `contracts.ts`
viem/wagmi contract configs:
- ABIs + addresses from `config/contracts.ts`.

### `demoTrader.ts`
Helper for “demo trader” logic:
- triggers repeated swaps on Uniswap v4 pool to generate fees for LP positions
- may call backend API routes or wagmi actions.

### `store/useHookEventStore.ts`
Zustand store that keeps a list of `SwapPriceLogged` events.  
Used by the dashboard to show an event timeline.

---

## 4. Environment Variables

Create `.env.local` in the web root:

```env
NEXT_PUBLIC_CHAIN_ID=11155111
NEXT_PUBLIC_RPC_URL=<sepolia_rpc_url>

NEXT_PUBLIC_STRATEGY_ROUTER_ADDRESS=0x...
NEXT_PUBLIC_STRATEGY_LENS_ADDRESS=0x...
NEXT_PUBLIC_AAVE_PROTOCOL_DATA_PROVIDER=0x...

# Optional: for demo trader / backend calls
BACKEND_RPC_URL=<node_used_by_api_routes>
