# Frontend ↔ Backend Integration Plan

> 작성: 2026-05-01  
> 기준: api-spec.md 실제 응답 shape + 현재 web/ 코드 분석 결과

---

## 현재 프론트 상태 요약

| 컴포넌트 | 데이터 출처 | 데이터 형태 |
|----------|-------------|-------------|
| `HookEventSection` | Zustand store (localStorage) | demo trader / user tx 이벤트 |
| `StrategyPositionCard` | on-chain (StrategyLens contract) | 포지션 상세 (USD 값, health factor 포함) |
| `UniswapPositionCard` | on-chain (StrategyLens contract) | Uniswap LP 포지션 |

백엔드 API를 직접 호출하는 컴포넌트는 현재 없다.  
유일한 백엔드 호출은 `/api/demo-trader/run` (Next.js API route 경유).

---

## 연동할 API 5개

### 1. `GET /api/pools/{poolId}/price-events?limit=20`

**연결 위치**: `HookEventSection`

**현재 상황**:
- `HookEventSection`은 Zustand store의 `events`를 표시한다
- 이 store는 demo trader 실행 후 또는 유저 tx 이후에 채워진다
- 페이지를 새로 열면 localStorage에서 복원되지만, 처음 방문이면 비어 있다

**연동 방식**:
- `HookEventSection` 마운트 시 백엔드에서 price events를 fetch
- 응답을 Zustand store에 `addMany`로 추가 (기존 UI 변경 없음)
- 중복 방지: txHash 기준으로 이미 store에 있는 이벤트는 skip
- poolId는 `NEXT_PUBLIC_POOL_ID` env로 주입

**데이터 변환**:
```
backend.poolId       → UiHookEvent.poolId
backend.tick         → UiHookEvent.tick
backend.sqrtPriceX96 → UiHookEvent.sqrtPriceX96
backend.txHash       → UiHookEvent.txHash
backend.eventTimestamp (ISO string) → timestampMs (Date.parse)
source               → "BACKEND"  (새 source 타입 추가)
```

---

### 2. `GET /api/users/{userAddress}/positions/open?limit=20`

**연결 위치**: `StrategyPositionCard` (기존 카드 하단에 보조 정보로 표시)

**현재 상황**:
- `StrategyPositionCard`는 on-chain `useStrategyPositionView`로 풍부한 데이터를 이미 보여준다
- 백엔드 응답은 더 단순: tokenId, ownerAddress, vaultAddress, supplyAsset, borrowAsset, isOpen, openedBlock, openedTxHash
- on-chain view를 대체하지 않고 보완한다

**연동 방식**:
- `StrategyPositionCard` 내부에서 wallet address 기준으로 fetch
- `openedBlock`, `openedTxHash`를 on-chain view가 없거나 rate limit일 때 fallback으로 활용
- 현재 구현: 기존 카드 하단에 "Opened at block #XXX (txHash...)" 형태로 작게 표시

---

### 3. `GET /api/positions/open?limit=20`

**연결 위치**: 새 섹션 `AllOpenPositionsCard` (page.tsx에 추가)

**현재 상황**: 전체 포지션 목록 보여주는 섹션 없음

**연동 방식**:
- `AllOpenPositionsCard` 컴포넌트 신규 작성
- 테이블 형태, 기존 `UniswapPositionCard` 스타일 재사용
- 컬럼: tokenId, owner (sliced), supplyAsset symbol, borrowAsset symbol, status

**page.tsx 변경**:
- `StrategyPositionCard` 아래에 `AllOpenPositionsCard` 추가

---

### 4. `GET /api/positions/{tokenId}/timeline?limit=20`

**연결 위치**: `StrategyPositionCard` 하단 (tokenId가 있을 때만 표시)

**현재 상황**: 타임라인 섹션 없음

**연동 방식**:
- on-chain view에서 `tokenId`를 얻은 후 timeline API 호출
- `metadata`는 JSON string → `JSON.parse()` 후 필요한 필드만 표시
- 이벤트 타입별 표시: `OPENED`, `CLOSED`, `LIQUIDITY_ADDED`, `FEES_COLLECTED` 등
- `StrategyPositionCard` 기존 Body 아래에 collapsible 없이 그냥 나열

**데이터**:
```json
{
  "tokenId": 20891,
  "eventType": "OPENED",
  "txHash": "0x...",
  "blockNumber": 9715930,
  "eventTimestamp": "2026-04-30T13:22:31.390017Z",
  "userAddress": "0x...",
  "vaultAddress": "0x...",
  "metadata": "{\"spent0\": \"...\", ...}"   // JSON string → parse 필요
}
```

---

### 5. `GET /api/positions/{tokenId}/snapshots?limit=20`

**연결 위치**: `StrategyPositionCard`에서 여는 히스토리 모달 내부

**현재 상황**:
- snapshot API는 최신순으로 상태 히스토리를 내려준다
- 응답 필드 중 bigint / decimal 계열 값은 string이다
- `healthFactor`는 일반적인 decimal string일 수도 있고, no-debt 포지션에서는 저장 가능한 최대 finite 값으로 요약되어 내려올 수 있다

**연동 방식**:
- 카드 본문을 복잡하게 늘리지 말고, `StrategyPositionCard` 안에 작은 버튼을 두고 모달을 띄운다
- 모달 안에서 `Activity`와 `Snapshots`를 분리해서 보여준다
- `Snapshots` 섹션은 `snapshotAt desc` 순서를 그대로 사용한다

**중요 UI 규칙**:
- 현재 카드 = 현재 상태
- 모달 = 히스토리
- snapshot은 이벤트가 아니라 상태 히스토리라는 점이 드러나야 한다

**healthFactor sentinel 처리 규칙**:
- 백엔드는 debt가 0인 포지션에서 컨트랙트가 `uint256 max`를 반환하면, DB 저장 시 `99999999999999999999.999999999999999999` 로 요약해서 내려준다
- 프론트는 이 값을 일반 숫자로 강하게 해석하지 말고, UI에서는 `No Debt`, `N/A`, `Very High` 같은 표현으로 풀어준다
- 이 값은 `Number()`로 변환하지 말고 string 비교 또는 전용 helper로 처리한다

**우선 표시할 필드**:
- `snapshotAt`
- `observedBlockNumber`
- `healthFactor`
- `totalCollateralBase`
- `totalDebtBase`
- `amount0Now`
- `amount1Now`

**권장 표시 방식**:
- `totalDebtBase === "0"` 이거나 sentinel 최대값이면 health factor 텍스트를 `No Debt`로 우선 표기
- 필요하면 보조 텍스트로 `Very High` 또는 `Infinite-like` 성격임을 설명
- 숫자 string은 정밀도 보존을 우선하고, 억지로 JS number로 바꾸지 않는다

---

## 파일 작업 계획

### 신규 파일

| 파일 | 역할 |
|------|------|
| `web/src/lib/backendApi.ts` | 백엔드 fetch 클라이언트. base URL은 `NEXT_PUBLIC_BACKEND_URL` env |
| `web/src/hooks/useBackendPriceEvents.ts` | price events fetch 훅 |
| `web/src/hooks/usePositionTimeline.ts` | timeline fetch 훅 |
| `web/src/hooks/useAllOpenPositions.ts` | 전체 포지션 fetch 훅 |
| `web/src/hooks/usePositionSnapshots.ts` | snapshot fetch 훅 |
| `web/src/components/dashboard/AllOpenPositionsCard.tsx` | 전체 포지션 섹션 |
| `web/src/components/modals/PositionHistoryModal.tsx` | activity + snapshots 히스토리 모달 |

### 수정 파일

| 파일 | 수정 내용 |
|------|----------|
| `web/src/components/dashboard/HookEventSection.tsx` | mount 시 백엔드 price events fetch → store 추가 |
| `web/src/components/dashboard/strategy/StrategyPositionCard.tsx` | 히스토리 모달 버튼 추가, backend user positions 보조 표시 |
| `web/src/app/page.tsx` | `AllOpenPositionsCard` 섹션 추가 |
| `web/src/store/useHookEventStore.ts` | `source` 타입에 `"BACKEND"` 추가 |
| `web/src/lib/backendApi.ts` | snapshot fetch / type 추가 |

### 환경 변수 추가 (`.env.local`)

```
NEXT_PUBLIC_BACKEND_URL=http://localhost:8080
NEXT_PUBLIC_POOL_ID=0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c
```

---

## 원칙

- 기존 on-chain 데이터 흐름(wallet, wagmi) 유지
- Zustand store는 그대로 사용, 백엔드 데이터를 추가로 채우는 방식
- loading / error / empty 세 상태 모두 처리
- metadata JSON string은 try/catch로 파싱 실패 시 raw string 표시
- snapshot의 `healthFactor` sentinel 최대값은 프론트에서 `No Debt` 계열 UI로 치환
- nextCursor 무시 (pagination 없음)
- CORS: 백엔드에서 `http://localhost:3000` origin 허용 필요 (Spring WebMvcConfig에서 설정)
