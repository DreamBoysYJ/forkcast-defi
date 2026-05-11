# Forkcast DeFi Contracts

**Forkcast DeFi contracts execute a one-button leveraged LP strategy by connecting Aave V3 and Uniswap v4.**

Users submit wallet transactions from the frontend, and the contracts handle the following flow.

```text
supply -> borrow -> swap -> LP
close -> remove LP -> swap back -> repay -> withdraw
```

The contracts are responsible for actual asset movement and DeFi protocol interactions. The backend later indexes events emitted by these contracts.

---

## 1. Goal

The goal of this package is to combine Aave V3 and Uniswap v4 into one strategy flow.

With one action, a user can:

1. supply collateral to Aave V3
2. borrow an asset against that collateral
3. swap part of the borrowed asset
4. create a Uniswap v4 LP position

When closing the position, the flow is reversed:

1. remove LP
2. swap back as needed
3. repay Aave debt
4. withdraw remaining collateral

---

## 2. Main Contracts

![Contract Architecture](../image-1.png)

### StrategyRouter

The main user entrypoint.

Main functions:

- `openPosition`
- `closePosition`
- `collectFees`
- `previewClosePosition`

Responsibilities:

- receive user ERC-20 assets and move them into the vault
- orchestrate Aave supply/borrow flow
- orchestrate Uniswap v4 swap/LP flow
- collect LP fees
- execute the close flow

`StrategyRouter` is the coordinator for the full strategy.

### UserAccount

A per-user vault contract.

Responsibilities:

- holds Aave collateral
- holds Aave debt position
- holds the Uniswap v4 LP NFT
- allows major actions only from the owner and `StrategyRouter`

Instead of making the user's EOA directly perform complex protocol interactions, the system manages assets through a per-user vault.

### AccountFactory

Creates and looks up per-user `UserAccount` vaults.

Responsibilities:

- manage the user -> vault mapping
- lazy-create vaults when needed
- let the frontend and backend look up vault addresses

### AaveModule

Handles Aave V3 interactions.

Main functions:

- supply
- borrow
- repay
- withdraw

Aave-related logic is separated to reduce `StrategyRouter` complexity.

### UniswapV4Module

Handles Uniswap v4 LP-related logic.

Main functions:

- create LP position
- remove LP
- collect fees
- perform v4 interactions required by the close flow

### MiniV4SwapRouter

A minimal Uniswap v4 swap router built only for this project.

Instead of bringing in the full Universal Router, it focuses on the swap flow this strategy needs.

Responsibilities:

- exact-input style swap
- used by strategy contracts and test helpers
- also usable by demo trader flows

### SwapPriceLoggerHook

An Uniswap v4 `AFTER_SWAP` hook.

Responsibilities:

- emit pool price information after swaps
- `tick`
- `sqrtPriceX96`
- timestamp
- pool id related data

The frontend can display these events, and the backend indexes them into the `pool_price_event` read model.

### StrategyLens

![Strategy Lens](../image-2.png)

A read-only view helper for both frontend and backend.

Responsibilities:

- read Aave reserve/user position data
- expose health factor, collateral, and debt
- compose strategy position views
- provide Uniswap v4 LP position overview
- let the snapshot job read current position state

---

## 3. Core Flows

### Open Position

```text
User
  -> StrategyRouter.openPosition
  -> AccountFactory.getOrCreate(user)
  -> UserAccount supplies collateral to Aave
  -> UserAccount borrows asset from Aave
  -> StrategyRouter swaps through MiniV4SwapRouter
  -> StrategyRouter adds liquidity to Uniswap v4
  -> LP NFT is owned by UserAccount
```

The contracts emit events, and the backend reads them later through the event-sync job.

### Collect Fees

```text
User
  -> StrategyRouter.collectFees(tokenId)
  -> verify vault owns LP tokenId
  -> collect fees from Uniswap v4
  -> transfer collected token0/token1 to user
```

Fee collection does not change LP liquidity.

### Close Position

```text
User
  -> StrategyRouter.closePosition
  -> remove Uniswap v4 liquidity
  -> swap withdrawn assets back to debt asset if needed
  -> repay Aave debt
  -> withdraw remaining collateral
  -> mark position closed
```

The close flow mirrors the open flow.

---

## 4. Backend Connection Points

The contracts and backend do not share execution authority.

The backend reads the following events and stores them in the DB:

- `PositionOpened`
- `PositionClosed`
- `FeesCollected`
- `SwapPriceLogged`

These events are transformed into backend read models:

- `strategy_position`
- `position_timeline`
- `pool_price_event`
- `position_snapshot`

Important points:

- Contracts are the execution source.
- The backend observes execution results.
- Users keep submitting transactions through their wallets.
- The backend does not store private keys.

---

## 5. Design Decisions

### Why per-user vaults?

Each user's `UserAccount` vault owns the Aave collateral, debt position, and Uniswap v4 LP NFT.

Compared with mixing all user positions in one shared vault, per-user vaults make ownership boundaries and permission checks clearer.  
The backend and frontend can also track positions through the user -> vault -> tokenId relationship.

### Why build `MiniV4SwapRouter`?

The official Universal Router is powerful, but it brings more functionality and complexity than this project needs.

`MiniV4SwapRouter` focuses on the exact-input style swap and demo/test flows needed by the strategy.  
This makes v4 interactions easier to read and keeps the test scope narrower.

### Why only an `AFTER_SWAP` hook?

`SwapPriceLoggerHook` is an observability hook that emits price information after swaps.

It intentionally avoids owning strategy execution or complex pool-state mutation responsibilities, keeping the hook's role close to observability.

### Why use HookMiner?

Uniswap v4 hook permissions are encoded in the hook contract address.

`HookMiner` is used to find a CREATE2 address that satisfies the desired flag combination, allowing the contract to be deployed as an `AFTER_SWAP` hook.

---

## 6. Folder Structure

```text
contracts
├─ src/
│  ├─ accounts/       # UserAccount vault
│  ├─ factory/        # AccountFactory
│  ├─ hook/           # SwapPriceLoggerHook, HookFactory
│  ├─ interfaces/     # Aave / Uniswap / ERC20 interfaces
│  ├─ lens/           # StrategyLens
│  ├─ libs/           # helper libraries
│  ├─ router/         # StrategyRouter, AaveModule, UniswapV4Module
│  ├─ types/          # shared structs/types
│  ├─ uniswapV4/      # MiniV4SwapRouter
│  └─ utils/          # utility contracts
├─ script/            # deployment / initialization scripts
└─ test/              # Foundry tests
```

---

## 7. Testing Focus

Tests cover:

- Uniswap v4 pool init / add liquidity / remove liquidity
- swap behavior and revert cases
- hook event emission
- openPosition happy path
- closePosition happy path
- collectFees happy path
- edge cases such as not owner, already closed, insufficient balance
- previewClosePosition sanity checks

Some tests run against Sepolia fork using real deployed Aave/Uniswap v4 addresses.  
They do not only test mocks; they verify happy paths and revert cases against real protocol addresses.

---

## 8. Local Development

Requirements:

- Foundry
- Sepolia RPC URL
- Aave V3 Sepolia addresses
- Uniswap v4 Sepolia addresses
- ERC-20 test tokens

Run:

```bash
cd contracts
cp .env.example .env
forge test
```

Example environment variables:

```text
SEPOLIA_RPC_URL=<your_rpc_url>
AAVE_POOL_ADDRESSES_PROVIDER=<address>
AAVE_PROTOCOL_DATA_PROVIDER=<address>
POOL_MANAGER=<address>
POSITION_MANAGER=<address>
PERMIT2=<address>
AAVE_UNDERLYING_SEPOLIA=<address>
LINK_UNDERLYING_SEPOLIA=<address>
WBTC_UNDERLYING_SEPOLIA=<address>
USER_ADDRESS=<test_user_address>
```

---

## 9. Design Limitations

This contract package is a technical prototype, not a production DeFi product.

Intentional simplifications:

- Sepolia only
- test tokens and custom demo pool
- single strategy flow
- single pool configuration
- LP tick range is wide for demo friendliness
- pricing/PnL may differ from real market behavior
- no upgradeability/proxy pattern

---

## 10. Related Docs

- [Root README](../README.eng.md)
- [Korean Contracts README](README.md)
- [Source README](src/README.md)
- [Backend README](../backend/README.eng.md)
- [API Spec](../api-spec.md)

