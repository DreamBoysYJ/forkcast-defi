# Forkcast DeFi (Sepolia Demo)

Aave V3 ↔ Uniswap v4 원샷 전략 + v4 Hook + DemoTrader (하우스) + Next.js 데모

## Packages

- `contracts/` Foundry (StrategyRouter, Hook, DemoTrader)
- `web/` Next.js (프론트 + API Routes)
- `infra/` IaC/배포 스크립트 (후순위)

## Quickstart

1. 복제 후 `.env.example`를 복사해 `.env` 세팅
2. `web`에서 `pnpm i && pnpm dev`
3. `contracts`에서 `forge build && forge test`
