# Forkcast DeFi Web

**Forkcast DeFi Web is a Next.js dApp frontend that combines wallet-based DeFi actions with backend history APIs.**

Users connect their wallets in the frontend and directly execute `StrategyRouter` transactions.  
The frontend reads on-chain state with wagmi/viem and enriches the UI with historical events and snapshots from the backend API.

---

## 1. Role

The frontend is responsible for:

- wallet connect
- Aave supply/borrow state display
- Strategy position state display
- Uniswap v4 LP position state display
- open / close / collect fee transactions
- Hook event timeline display
- position history, open positions, and snapshot data through backend APIs

Important principles:

- User write actions continue to be wallet transactions.
- The backend does not submit transactions on behalf of users.
- Backend data is used for history and supporting query views.
- The existing wagmi/viem on-chain read/write flow is preserved.

---

## 2. Tech Stack

- Next.js App Router
- TypeScript
- React
- wagmi
- viem
- Zustand
- CSS modules / global CSS

---

## 3. Main User Flows

### Open Position

1. The user connects a wallet.
2. The frontend reads Aave reserves, wallet balances, and strategy state.
3. The user enters open-position parameters.
4. The frontend requests a `StrategyRouter.openPosition` transaction from the wallet.
5. After submission, the frontend may send the tx hash to the backend as a tx hint.
6. Once backend event-sync confirms the actual on-chain event, the history UI can update.

### Close / Collect

1. The frontend displays current position and LP state.
2. The user chooses close or collect fee.
3. The frontend requests a `closePosition` or `collectFees` transaction from the wallet.
4. After backend event-sync, timeline and open-position read models update.

### History / Snapshot

1. The frontend reads current state from on-chain views.
2. It additionally fetches timelines, price events, and snapshots from backend APIs.
3. Current state and historical data are displayed separately.

---

## 4. Backend API Integration

The frontend consumes these APIs:

| API | Used in | Purpose |
| --- | --- | --- |
| `GET /api/pools/{poolId}/price-events` | Hook event section | Show Hook price event history |
| `GET /api/users/{userAddress}/positions/open` | Strategy position area | Supporting info for my open positions |
| `GET /api/positions/open` | All open positions | List all open positions |
| `GET /api/positions/{tokenId}/timeline` | Position history | Show position lifecycle |
| `GET /api/positions/{tokenId}/snapshots` | Position history modal | Show state snapshot history |
| `POST /api/tx-hints` | After transaction submission | Store pending transaction hints |

See [api-spec.md](../api-spec.md) for response shapes.

---

## 5. Integration Notes

### `NEXT_PUBLIC_BACKEND_URL` is a build-time value

Next.js injects `NEXT_PUBLIC_*` environment variables into the bundle at `npm run build` time.

Changing Cloud Run runtime env vars alone does not update the backend URL in an already-built JS bundle.  
Deployment must pass `_NEXT_PUBLIC_BACKEND_URL` through `cloudbuild.yaml` substitutions as a build arg.

### Address normalization

Backend query APIs use lower-case address normalization for comparisons.  
When the frontend places a user address in a query path, it should apply `toLowerCase()`.

### healthFactor sentinel

When a position has no debt, the contract may return a very large health factor.  
The backend may summarize it as the largest storable finite value, and the frontend should not force it into a normal JavaScript number.

The UI should display it as `No Debt`, `Very High`, or `N/A`.

### metadata JSON string

The timeline API may return `metadata` as a JSON string.  
The frontend should wrap `JSON.parse()` in try/catch and fall back to the raw string if parsing fails.

---

## 6. Folder Structure

```text
src
├─ abi/
├─ app/
│  ├─ api/
│  ├─ globals.css
│  ├─ layout.tsx
│  └─ page.tsx
├─ components/
│  ├─ common/
│  ├─ dashboard/
│  ├─ modals/
│  ├─ Connect.tsx
│  └─ Providers.tsx
├─ config/
├─ hooks/
└─ lib/
   ├─ chain.ts
   ├─ contracts.ts
   ├─ backendApi.ts
   ├─ demoTrader.ts
   └─ store/
```

---

## 7. Local Development

```bash
cd web
cp .env.example .env.local
npm install
npm run dev
```

Example environment variables:

```text
NEXT_PUBLIC_CHAIN_ID=11155111
NEXT_PUBLIC_RPC_URL=<sepolia_rpc_url>
NEXT_PUBLIC_BACKEND_URL=http://localhost:8080
NEXT_PUBLIC_POOL_ID=<uniswap_v4_pool_id>

NEXT_PUBLIC_STRATEGY_ROUTER_ADDRESS=<router_address>
NEXT_PUBLIC_STRATEGY_LENS_ADDRESS=<lens_address>
NEXT_PUBLIC_AAVE_PROTOCOL_DATA_PROVIDER=<aave_data_provider>
```

---

## 8. Related Docs

- [Korean Web README](README.md)
- [Root README](../README.eng.md)
- [API Spec](../api-spec.md)
- [Frontend Backend Integration Plan](../docs/frontend/backend-integration-plan.md)
- [Cloud Run Frontend Deploy Guide](infra/cloud-run/README.md)

