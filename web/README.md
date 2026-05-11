# Forkcast DeFi Web

**Forkcast DeFi Web은 지갑 기반 DeFi 액션과 백엔드 히스토리 API를 함께 보여주는 Next.js dApp 프론트엔드입니다.**

사용자는 프론트엔드에서 지갑을 연결하고, `StrategyRouter` 트랜잭션을 직접 실행합니다.  
프론트엔드는 온체인 상태를 wagmi/viem으로 읽고, 백엔드 API를 통해 과거 이벤트와 스냅샷 데이터를 보강합니다.

---

## 1. 역할

프론트엔드는 다음 책임을 가집니다.

- wallet connect
- Aave supply/borrow 상태 표시
- Strategy position 상태 표시
- Uniswap v4 LP position 상태 표시
- open / close / collect fee 트랜잭션 실행
- Hook event timeline 표시
- 백엔드 API를 통한 position history, open position, snapshot 데이터 표시

중요한 원칙:

- 사용자의 write action은 계속 지갑 트랜잭션으로 실행합니다.
- 백엔드는 사용자 대신 트랜잭션을 보내지 않습니다.
- 백엔드 데이터는 히스토리/보조 조회 데이터로 사용합니다.
- 기존 wagmi/viem 온체인 read/write flow를 유지합니다.

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

## 3. 주요 사용자 흐름

### Open Position

1. 사용자가 지갑을 연결합니다.
2. 프론트가 Aave reserve, wallet balance, strategy 상태를 읽습니다.
3. 사용자가 포지션 오픈 파라미터를 입력합니다.
4. 프론트가 `StrategyRouter.openPosition` 트랜잭션을 지갑에 요청합니다.
5. 트랜잭션 제출 후 tx hash를 백엔드에 tx hint로 보낼 수 있습니다.
6. 백엔드 event-sync가 실제 온체인 이벤트를 확인하면 히스토리 UI가 갱신됩니다.

### Close / Collect

1. 프론트가 현재 position과 LP 상태를 표시합니다.
2. 사용자가 close 또는 collect fee 액션을 선택합니다.
3. 프론트가 `closePosition` 또는 `collectFees` 트랜잭션을 지갑에 요청합니다.
4. 백엔드 event-sync 이후 timeline과 open position read model이 갱신됩니다.

### History / Snapshot

1. 프론트는 현재 상태를 온체인 view로 읽습니다.
2. 백엔드 API로 timeline, price events, snapshots를 추가 조회합니다.
3. 현재 상태와 히스토리성 데이터를 분리해서 표시합니다.

---

## 4. 백엔드 API 연동

프론트는 다음 API를 소비합니다.

| API | 사용 위치 | 목적 |
| --- | --- | --- |
| `GET /api/pools/{poolId}/price-events` | Hook event section | Hook price event 히스토리 표시 |
| `GET /api/users/{userAddress}/positions/open` | Strategy position area | 내 오픈 포지션 보조 정보 |
| `GET /api/positions/open` | All open positions | 전체 오픈 포지션 목록 |
| `GET /api/positions/{tokenId}/timeline` | Position history | 포지션 lifecycle 표시 |
| `GET /api/positions/{tokenId}/snapshots` | Position history modal | 상태 스냅샷 히스토리 표시 |
| `POST /api/tx-hints` | transaction submit 이후 | pending tx hint 저장 |

백엔드 API의 상세 응답 형식은 [../api-spec.md](../api-spec.md)를 확인합니다.

---

## 5. 프론트 연동 주의사항

### NEXT_PUBLIC_BACKEND_URL은 build-time 값

Next.js의 `NEXT_PUBLIC_*` 환경 변수는 `npm run build` 시점에 번들에 삽입됩니다.

Cloud Run runtime env만 바꿔서는 이미 빌드된 JS bundle의 백엔드 URL이 바뀌지 않습니다.  
배포 시 `cloudbuild.yaml`의 `_NEXT_PUBLIC_BACKEND_URL` substitution으로 build arg를 주입해야 합니다.

### address normalization

백엔드 조회 API는 주소 비교를 위해 lower-case 정규화를 사용합니다.  
프론트에서 user address를 query path에 넣을 때는 `toLowerCase()`를 적용합니다.

### healthFactor sentinel

debt가 없는 포지션에서 컨트랙트가 매우 큰 health factor 값을 반환할 수 있습니다.  
백엔드는 저장 가능한 최대 finite 값으로 요약할 수 있고, 프론트는 이를 일반 숫자로 강제 변환하지 않습니다.

UI에서는 `No Debt`, `Very High`, `N/A` 같은 표현으로 풀어 표시합니다.

### metadata JSON string

timeline API의 `metadata`는 JSON string으로 내려올 수 있습니다.  
프론트는 `JSON.parse()`를 try/catch로 감싸고, 실패하면 raw string을 fallback으로 표시합니다.

---

## 6. 폴더 구조

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

환경 변수 예시:

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

## 8. 관련 문서

- [README.md](README.md)
- [../readme-draft.ko.md](../readme-draft.ko.md)
- [../api-spec.md](../api-spec.md)
- [../docs/frontend/backend-integration-plan.md](../docs/frontend/backend-integration-plan.md)
- [infra/cloud-run/README.md](infra/cloud-run/README.md)
