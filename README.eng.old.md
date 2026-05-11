# Forkcast DeFi

🌐 Languages: [한국어 README](README.ko.md)

One-button leveraged LP strategy demo on **Aave V3 + Uniswap v4 (Sepolia)**.  
Turns “supply → borrow → swap → LP → close” into a single, inspectable flow.

---

## 1. What is Forkcast DeFi?

![alt text](image.png)

Forkcast DeFi is a one-shot DeFi strategy demo:

1. Supply an ERC-20 asset on Aave V3 as collateral
2. Borrow against that collateral
3. Swap part of the borrowed asset and provide Uniswap v4 liquidity
4. A custom hook logs swap events so you can _see_ the strategy in action
5. Close the position: remove LP → swap back → repay debt → withdraw collateral

This repo is a monorepo with:

- **contracts/** – Foundry-based smart contracts (Aave V3 + Uniswap v4 strategy)
- **web/** – Next.js dashboard & demo UI (wagmi/viem, Zustand, React Query)

---

## 2. Live Demo & Presentation Video (Eng sub o) <-- Please Watch this first!

- 🔗 **Live dApp**: <https://forkcast-web-799298411936.asia-northeast3.run.app/>
- 🎥 **YouTube**: <https://youtu.be/3bI2R2cJe6c?si=HLHtmrSIzuoiiXxS>

You must prepare some ETH and ERC-20 tokens that Aave protocol created.

- **Aave Sepolia Faucet** : <https://gho.aave.com/faucet/>
- **Sepolia ETH Faucet** : <https://sepolia-faucet.pk910.de/>

---

## 3. Monorepo Structure

```text
.
├─ contracts/   # Foundry smart contracts: Router, Vault, Lens, Hook, etc.
└─ web/         # Next.js app: dashboard, strategy UI, demo trader controls
```

Contracts docs: [contracts/README.md](contracts/README.md)  
Web app docs: [web/README.md](web/README.md)

---

## 4. High-Level Architecture

![alt text](image-1.png)

### StrategyRouter

Orchestrates `supply → borrow → swap → LP` and the reverse `close` flow.

### AccountFactory / UserAccount (vault)

Per-user vault that owns aTokens, debt positions, and the Uniswap v4 LP NFT.

### MiniV4SwapRouter

Instead of using Uniswap v4 Universal Router, I built v4 router for swaps only.

### StrategyLens

![alt text](image-2.png)

Read-only views for:

- Aave reserves & user positions (HF, collateral, debt)
- Strategy positions (tokenId, vault address, tick range, liquidity)
- LP fee & position overview

### Uniswap v4 Module + Hook

Adds/removes liquidity, collects fees, and logs swap events for the UI.

### Web (Next.js)

Connects with MetaMask, calls Router/Lens, renders HF, tick ranges, LP liquidity,  
and displays hook-generated event logs (**“Your swap”**).

---

## 5. Quick Start (Development)

### 5.1 Clone

```bash
git clone https://github.com/yourname/forkcast-defi.git
cd forkcast-defi
```

### 5.2 Contracts (Foundry)

```bash
cd contracts
cp .env.example .env    # fill in Sepolia RPC URL & Aave/Uniswap addresses
forge test
```

### 5.3 Web (Next.js)

```bash
cd ../web
cp .env.example .env    # paste deployed contract addresses from contracts
npm i
npm run dev
```

Then open http://localhost:3000
and follow along with the YouTube video.

---

## 6. Tech Stack

### App / Backend

- **Next.js** (App Router, API Routes)
  - Dashboard UI, modals
- **TypeScript + React**
- **wagmi + viem** (on-chain calls)
- **Zustand** (hook event / position state management)

### Smart Contracts

- **Foundry** (development, testing, deployment)
- **Solidity**

### Infra

- **Google Cloud Run**
- **RPC providers**: Infura / Alchemy (Sepolia)

---

## 7. Important Notes & Limitations

1. **Non-official tokens & pools**

   - Aave assets in Sepolia are custom tokens, so I created a custom pool.
   - Real users will not trade in these pools, so PnL can be very different from production.

2. **Simplified pricing**

   - Aave oracle prices are treated as fixed, and the Uniswap v4 pool is initialized 1:1.
   - Please do not interpret this as a realistic market price.

3. **Always-in-range liquidity**

   - LP positions are opened with a very wide tick range so that fees are generated easily for the demo.

4. **Tech-first prototype**
   - The goal of this project is technical learning and implementation.
   - Some design choices may be unrealistic for a real DeFi product.

---

## 8. Technical & Personal Learnings

1. **My own architecture almost confused me**

   - The architecture got bigger and more tangled → I could even get lost in a system I designed myself.
   - It reminds me how much I still have to improve.

2. **Specs and communication matter more than I thought.**

   - For a real team project, clear docs and shared interfaces between frontend, backend, and contracts are important.

3. **Review DeFi & Blogging to find better ideas**
   - I realized this level of design means I still don’t fully understand DeFi end-to-end.
   - I’m blogging to revisit the math and code details, and building on my previous contribution to the Cyfrin DeFi course to deepen my understanding.

---

## 9. Next Steps & Future Work

1. **Strategy-aware asset suggestions**

   - Recommend supply/borrow assets based on risk, expected yield, and price scenarios.
   - (e.g. higher HF vs more aggressive leverage options)

2. **Off-chain indexer & backend API**

   - Build a small indexer that listens to events related to this service, and stores positions & PnL history in a DB.
   - Please do not interpret this as a realistic market price.

3. **Repositioning hook & alert**

   - Extend the Swap Logger Hook to detect when a position is near or outside its tick range,
   - and send **“reposition recommended”** signals to the frontend or backend notifier.

4. **Repositioning hook & alert**
   - Extend the Swap Logger Hook to detect when a position is near or outside its tick range,
   - and send **“reposition recommended”** signals to the frontend or backend notifier.

---

## 10. Thanks to

Special thanks to Cyfrin and t4sk for providing the best DeFi courses I’ve ever taken.
I’ll keep studying hard and do my best to contribute more as a community contributor.

- **Cyfrin/UniswapV4 Contributor**: <https://github.com/Cyfrin/defi-uniswap-v4>
