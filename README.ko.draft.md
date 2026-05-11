# Forkcast DeFi

**Aave V3 + Uniswap v4 기반 원버튼 레버리지 LP dApp과, 온체인 이벤트를 인덱싱하는 Spring Boot 백엔드 프로젝트입니다.**

Forkcast DeFi는 사용자가 지갑으로 직접 트랜잭션을 보내고, 스마트 컨트랙트가 Aave V3와 Uniswap v4를 이용해 `supply -> borrow -> swap -> LP -> close` 흐름을 실행하는 DeFi 데모입니다.

현재 버전은 여기에 Spring Boot 백엔드를 추가해, 온체인 이벤트와 포지션 상태를 DB에 저장하고 조회 API로 제공하는 구조까지 포함합니다.

![Forkcast DeFi UI](image.png)

---

## Live Demo

- Live dApp: <https://forkcast-web-799298411936.asia-northeast3.run.app/>
- YouTube: <https://youtu.be/3bI2R2cJe6c?si=HLHtmrSIzuoiiXxS>

데모를 사용하려면 Sepolia ETH와 Aave Sepolia 테스트 토큰이 필요합니다.

- Aave Sepolia Faucet: <https://gho.aave.com/faucet/>
- Sepolia ETH Faucet: <https://sepolia-faucet.pk910.de/>

---

## 전체 구조

```text
.
├─ contracts/   # Aave V3 + Uniswap v4 전략 컨트랙트
├─ backend/     # Spring Boot 온체인 이벤트 인덱서 / 조회 API
├─ web/         # Next.js dApp 프론트엔드
└─ docs/        # API, 백엔드 설계, 운영, QA 문서
```

![Architecture](image-1.png)

사용자는 프론트엔드에서 지갑을 연결하고 컨트랙트 트랜잭션을 직접 실행합니다.  
백엔드는 사용자 대신 트랜잭션을 보내지 않고, 온체인에서 발생한 이벤트를 읽어 포지션 히스토리와 스냅샷을 만듭니다.

---

## 지원 분야별로 보기

### 백엔드 / 블록체인 백엔드

백엔드는 off-chain indexer/query backend입니다.

주요 포인트:

- Spring Boot + Java 21
- PostgreSQL + Flyway
- Web3j 기반 Router/Hook event sync
- raw event와 read model 분리
- pending tx hint와 온체인 이벤트 reconciliation
- position timeline / pool price event / snapshot API
- Cloud Scheduler + job lock + sync cursor

자세히 보기:

- [backend/README.ko.draft.md](backend/README.ko.draft.md)
- [api-spec.md](api-spec.md)
- [docs/backend/goal.md](docs/backend/goal.md)
- [docs/backend/data-model.md](docs/backend/data-model.md)
- [docs/backend/scheduler-plan.md](docs/backend/scheduler-plan.md)

### 스마트 컨트랙트

컨트랙트는 Aave V3와 Uniswap v4를 연결해 원버튼 레버리지 LP 전략을 실행합니다.

주요 포인트:

- `StrategyRouter` 중심의 open/close/collect flow
- 사용자별 `UserAccount` vault
- Aave supply/borrow/repay/withdraw 연동
- Uniswap v4 LP 생성, 제거, 수수료 수집
- `SwapPriceLoggerHook` 기반 이벤트 로깅
- `StrategyLens` view helper

자세히 보기:

- [contracts/README.ko.draft.md](contracts/README.ko.draft.md)
- [contracts/README.md](contracts/README.md)
- [contracts/src/README.md](contracts/src/README.md)

### 프론트엔드

프론트엔드는 지갑 기반 DeFi UX를 담당합니다.

주요 포인트:

- Next.js + TypeScript
- wagmi / viem 기반 wallet transaction
- Aave, Uniswap v4, StrategyRouter 상태 표시
- 백엔드 API를 통한 히스토리 데이터 보강
- hook event, open position, timeline, snapshot UI 연동

자세히 보기:

- [web/README.md](web/README.md)
- [docs/frontend/backend-integration-plan.md](docs/frontend/backend-integration-plan.md)

---

## 핵심 흐름

### 사용자 트랜잭션 흐름

```text
User Wallet
  -> Next.js Frontend
  -> StrategyRouter
  -> UserAccount vault
  -> Aave V3 + Uniswap v4
```

사용자 자산과 실행 권한은 지갑과 컨트랙트에 남아 있습니다.

### 백엔드 인덱싱 흐름

```text
Cloud Scheduler
  -> Spring Boot internal job
  -> RPC eth_getLogs / eth_call
  -> PostgreSQL raw events / read models / snapshots
  -> Frontend query APIs
```

백엔드는 온체인에서 이미 일어난 일을 저장하고, 프론트엔드가 조회하기 쉬운 형태로 제공합니다.

---

## 주요 API

```text
GET  /api/pools/{poolId}/price-events
GET  /api/users/{userAddress}/positions/open
GET  /api/positions/open
GET  /api/positions/{tokenId}/timeline
GET  /api/positions/{tokenId}/snapshots
POST /api/tx-hints
```

내부 job endpoint:

```text
POST /internal/jobs/event-sync
POST /internal/jobs/snapshot
```

자세한 응답 형식은 [api-spec.md](api-spec.md)를 확인합니다.

---

## Tech Stack

### Smart Contracts

- Solidity
- Foundry
- Aave V3
- Uniswap v4

### Backend

- Java 21
- Spring Boot
- PostgreSQL
- Flyway
- Web3j
- Google Cloud Run
- Google Cloud Scheduler

### Frontend

- Next.js
- TypeScript
- React
- wagmi
- viem
- Zustand

---

## Quick Start

### Contracts

```bash
cd contracts
cp .env.example .env
forge test
```

### Backend

```bash
cd backend
./gradlew test
./gradlew bootRun
```

### Web

```bash
cd web
cp .env.example .env.local
npm install
npm run dev
```

---

## 한계

이 프로젝트는 실제 운용 가능한 DeFi 상품이 아니라, DeFi와 백엔드 시스템 설계를 학습하고 보여주기 위한 technical prototype입니다.

- Sepolia 테스트넷 기준
- 테스트 토큰과 데모 풀 사용
- 실제 시장 가격/PnL과 다를 수 있음
- 백엔드 sync는 완전 실시간이 아님
- v1은 단순한 safe-head sync 정책 사용
- advanced analytics, alerting, admin dashboard는 future work

---

## 포트폴리오 관점

이 프로젝트는 다음 역량을 보여주기 위해 구성했습니다.

- DeFi 컨트랙트 흐름 이해
- Aave V3 / Uniswap v4 통합
- 지갑 기반 트랜잭션과 백엔드 책임 분리
- 온체인 이벤트 인덱싱 설계
- Spring Boot + PostgreSQL API 서버 구현
- scheduled job, cursor, lock 기반 운영 설계
- 프론트엔드와 백엔드 API 연동

핵심 방향:

> 사용자의 자산 실행 권한은 지갑과 컨트랙트에 남기고, 백엔드는 온체인에서 이미 일어난 일을 안정적으로 기록하고 조회 가능하게 만든다.

