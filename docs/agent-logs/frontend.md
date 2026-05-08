# Frontend Agent Log

## 2026-05-08 demo trader 사전 approve 전제 반영 ✓

- 작업 목적
  - demo trader 실행 때마다 발생하던 ERC-20 approve tx 2개를 제거하고, 미리 approve된 전용 지갑만 쓰도록 정리
- 읽은 파일
  - `docs/frontend/backend-integration-plan.md`
  - `web/src/lib/demoTrader.ts`
- 변경한 파일
  - `web/src/lib/demoTrader.ts`
  - `docs/agent-logs/frontend.md`
- 한 일
  - demo trader가 더 이상 매 실행마다 `approve(AAVE)` / `approve(LINK)`를 보내지 않도록 approve 블록을 제거했다
  - 주어진 demo trader 공개 주소 `0xde589C867174C349d00e9b582867aF5c13A74679`를 상수로 두고, 서버에 설정된 private key가 이 주소와 일치하는지 검증하도록 추가했다
- 왜 그렇게 했는지
  - 버튼 한 번에 불필요한 tx 두 건이 더 나가고, allowance가 이미 충분한 상황에서도 매번 approve를 반복하는 구조였기 때문이다
  - 공개 주소만 코드에 고정하고 실제 서명키는 서버 env로 유지하면, 원하는 계정을 강제하면서도 비밀키를 코드에 넣지 않아도 된다
- 남은 문제
  - 운영 배포 환경의 `DEMO_TRADER_PRIVATE_KEY`도 위 공개 주소와 짝이 맞게 설정돼 있어야 한다

## 2026-05-04 Position activity 섹션 — 전체 포지션 accordion 구조로 변경 ✓

- 작업 목적
  - 기존에 `positions[0]` 하나만 보이던 구조 → 전체 오픈 포지션 accordion으로 변경
  - 페이지가 길어지는 문제 해결: 기본 접힘, 클릭 시 펼침
- 변경한 파일
  - `web/src/components/dashboard/strategy/PositionActivitySection.tsx`
    - `firstTokenId` 단일 조회 → `positions` 전체 목록 기반 렌더링
    - `CollapsibleTimeline` 컴포넌트 추가: tokenId 헤더 클릭 시 expand, timeline fetch도 `enabled: isOpen`으로 lazy load
    - 헤더 설명 텍스트 → "Click a position to expand its timeline"
    - 포지션 수 표시 (N positions)
- 왜 그렇게 했는지
  - 페이지가 이미 길어서 기본 접힘 필수
  - timeline API는 펼칠 때만 호출 → 불필요한 백엔드 요청 없음
- 남은 문제
  - 없음

---

## 2026-05-04 Collect fees를 Strategy overview로 이동, UniswapPositionCard 제거 ✓

- 작업 목적
  - "Your Uniswap LP" 섹션 제거, collect fees 기능을 Strategy overview 각 포지션 row에 통합
- 읽은 파일
  - `web/src/components/dashboard/UniswapPositionCard.tsx`
  - `web/src/components/modals/CollectFeesModal.tsx`
  - `web/src/app/page.tsx`
- 변경한 파일
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
    - `useConfig`, `useAccount`, `simulateContract`, `writeContract`, `waitForTransactionReceipt` 추가
    - collect fees 관련 state (`collectPosition`, `isCollectOpen`, `isCollectProcessing`) 추가
    - `handleCollectClick` / `handlePreviewCollect` / `handleExecuteCollect` 핸들러 추가
    - `CollectFeesModal` 렌더링 추가
  - `web/src/components/dashboard/strategy/StrategyPositionRow.tsx`
    - `onClickCollect?: (tokenId: number) => void` prop 추가
    - "Collect fees" 버튼 추가 (`bg-emerald-600` solid fill, History/Preview close 사이)
  - `web/src/app/page.tsx`
    - `UniswapPositionCard` import 및 렌더링 제거
- 왜 그렇게 했는지
  - Uni LP 정보(pool, range, amounts)는 Strategy overview row에 이미 표시됨 → 중복 UI 제거
  - collect fees 로직은 `UniswapPositionCard`에서 `simulateContract` + `writeContract` 패턴 그대로 이식
  - 버튼 색상 emerald (초록 solid)으로 눈에 띄게 — History(grey), Preview close(indigo tint)와 구분
- 남은 문제
  - `UniswapPositionCard.tsx`, `UniswapPositionRow.tsx`, `useUserUniPositions.ts` 파일은 아직 남아 있음
  - `UniswapPositionRow.tsx`는 `CollectFeesModal`이 `UniPositionRowData` 타입을 import하므로 삭제 불가
  - `UniswapPositionCard.tsx`, `useUserUniPositions.ts`는 더 이상 사용되지 않으나 cleanup은 나중에

---

## 2026-05-04 Strategy overview 다중 포지션 표시 ✓

- 작업 목적
  - 오픈 포지션이 여러 개일 때 하나만 보이던 문제 수정 → 전부 표시
- 읽은 파일
  - `web/src/hooks/useStrategyPositionView.ts`
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
  - `web/src/components/dashboard/strategy/StrategyPositionRow.tsx`
- 변경한 파일
  - `web/src/hooks/useStrategyPositionView.ts`
    - 반환값 `view: StrategyPositionView | null` → `views: StrategyPositionView[]`
    - 오픈 포지션 전부 수집, 없으면 가장 마지막 closed 1개 fallback
  - `web/src/components/dashboard/strategy/StrategyPositionRow.tsx`
    - `onClickHistory?: (tokenId: number) => void` prop 추가
    - "History" 버튼을 "Preview close" 버튼 왼쪽에 추가
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
    - `views` 배열 기반 리스트 렌더링 (divide-y 구분선)
    - History/Close 모달이 각자 클릭된 tokenId 추적 (`snapshotTokenId` state 추가)
    - 헤더 Open/Closed 뱃지 제거 (각 row에 이미 있음)
    - `toRowData()` 헬퍼 함수로 view → StrategyPositionRowData 변환 분리
- 왜 그렇게 했는지
  - 기존 훅은 `break`로 첫 open 포지션 하나만 선택 → 의도적 단일 표시였지만 요구사항 변경
  - Close/History 모달은 기존처럼 tokenId 기반 상태로 관리, 다중 포지션에서도 올바른 tokenId 전달
- 남은 문제
  - 없음

---

## 2026-05-04 Snapshot history 모달 연동 (plan 5번) ✓

- 작업 목적
  - `GET /api/positions/{tokenId}/snapshots` 연동, StrategyPositionCard에 History 버튼 + 모달 표시
- 읽은 파일
  - `docs/frontend/backend-integration-plan.md` (5번 항목)
  - `api-spec.md` (1-5)
  - `web/src/components/modals/PositionSnapshotModal.tsx`
  - `web/src/lib/backendApi.ts`
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
  - `web/src/components/dashboard/strategy/StrategyPositionRow.tsx`
- 변경한 파일
  - `web/src/components/modals/PositionSnapshotModal.tsx`
    - `isNoDebt(s)` 헬퍼 추가: `totalDebtBase === "0"` 또는 healthFactor가 `"9999999999..."` 로 시작하면 true
    - HF 셀: sentinel이면 `"No Debt"` (emerald 색), 아니면 기존 parseFloat 기반 색상 + `fmtHF` 표시
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
    - 카드 헤더에 `History` 버튼 추가 (포지션 있을 때만, Open/Closed 뱃지 왼쪽)
    - `<PositionSnapshotModal>` 렌더링 연결 (rowData가 있을 때 tokenId 전달)
- 왜 그렇게 했는지
  - `PositionSnapshotModal.tsx`와 `backendApi.ts`의 snapshot 관련 코드는 이미 구현되어 있었음
  - `StrategyPositionCard`에 `isSnapshotOpen` state와 import는 있었으나 버튼/렌더링이 빠져 있었음
  - sentinel값을 `Number()`로 변환하면 정밀도 손실 → string prefix 비교로 처리
- 남은 문제
  - plan 기준으로 구현 완료. 백엔드 snapshot job이 실제로 데이터를 수집해야 UI에서 내용이 보임

---

## 2026-05-01 snapshot healthFactor sentinel 프론트 메모 추가 ✓

- 작업 목적
  - Claude Code 프론트 작업자가 snapshot API의 `healthFactor` sentinel 규칙을 놓치지 않게 문서에 남긴다
- 읽은 파일
  - `docs/frontend/backend-integration-plan.md`
  - `docs/agent-logs/frontend.md`
- 변경한 파일
  - `docs/frontend/backend-integration-plan.md`
  - `docs/agent-logs/frontend.md`
- 한 일
  - snapshot API 섹션을 추가하고, `GET /api/positions/{tokenId}/snapshots` 연동 위치를 `StrategyPositionCard`의 히스토리 모달로 명시했다
  - no-debt 포지션의 `healthFactor`가 백엔드에서 최대 finite 값으로 요약될 수 있다는 점과, 프론트는 이를 `No Debt` / `Very High` 같은 표현으로 풀어야 한다는 규칙을 적었다
- 왜 그렇게 했는지
  - 프론트가 이 값을 일반 숫자로 처리하면 UX가 어색하고, 잘못하면 다시 `Number()` 기반 정밀도 문제가 생긴다
  - 프론트 담당이 작업 시작 전에 읽는 문서에 직접 있어야 실제 구현에서 반영된다
- 남은 문제
  - 실제 UI 구현은 아직 프론트 담당 작업이 남아 있다

## 2026-05-01 브랜치 생성 및 푸시 ✓

- 브랜치: `claude-frontend` (base: `cluade-setup`)
- 커밋: `4626990` — feat(web): integrate backend APIs and fix transaction flow
- 포함된 파일: 오늘 작업한 web/ 프론트 파일 14개 + docs/agent-logs/frontend.md
- 백엔드 staged 파일은 제외하고 프론트 파일만 선택적으로 커밋
- 원격 푸시: `origin/claude-frontend`

---

## 2026-05-01 전체 활성 포지션 모달 연동 (1-3) ✓

- 작업 목적
  - `GET /api/positions/open` 연동, 전체 오픈 포지션 목록을 모달로 표시
- 읽은 파일
  - `api-spec.md`
  - `web/src/lib/backendApi.ts`
  - `web/src/app/page.tsx`
- 변경한 파일
  - `web/src/lib/backendApi.ts` — `fetchAllOpenPositions(limit)` 추가
  - `web/src/components/modals/AllPositionsModal.tsx` (신규) — 전체 포지션 테이블 모달
  - `web/src/app/page.tsx` — 상단 우측 "All positions" 버튼 + 모달 연결
- 동작
  - 상단 우측 "All positions" 버튼 클릭 → 모달 오픈
  - 모달 열릴 때 `fetchAllOpenPositions(50)` 호출
  - 테이블 컬럼: Token ID | Owner(단축) | Strategy(supply→borrow) | Opened Block
  - asset address → AAVE/LINK 심볼 변환 (ASSET_LABELS lookup)
  - 로딩/에러/빈 상태 모두 처리
- 왜 그렇게 했는지
  - 페이지가 이미 꽉 차 있어 모달로 분리
  - 기존 Connect/Demo Trader 버튼 왼쪽 배치 유지, 우측에 새 버튼 추가
  - 모달은 열릴 때만 fetch (불필요한 백그라운드 호출 없음)
- 남은 문제
  - 없음

---

## 2026-05-01 supplyAmount 잔액 초과로 인한 ERC20 revert 수정 ✓

**현상**
- openPosition 트랜잭션이 `ERC20: transfer amount exceeds balance`로 revert
- 화면에는 잔액이 충분해 보이는데도 실패

**원인**
`useEffect`에서 잔액 기본값을 `Number(raw) / Math.pow(10, dec)` 기반 float 계산 후 `.toFixed(2)`로 채웠음.
`.toFixed(2)`는 반올림이므로 실제 잔액이 `99.998...` 토큰이면 `"100.00"`으로 기본값이 설정됨.
approve는 `"100.00"`으로 성공(approve는 금액 초과 허용)하지만, `transferFrom` 시 실제 잔액 초과로 revert.

**수정**
- `formatUnits` import 추가 (viem) — bigint → 정확한 소수 문자열 변환
- 기본값 계산: `formatUnits` + 문자열 슬라이싱으로 소수 2자리 내림(floor), 반올림 없음
- `supplyAmountExceedsBalance` useMemo 추가: `parseUnits(input) > actualBalance`
- 입력 필드 border 빨간색 + 인라인 에러 메시지(`Exceeds wallet balance (X.XX AAVE)`) 표시
- approve 버튼 `disabled` 조건에 `supplyAmountExceedsBalance` 추가
- approve 직전 guard: `amountBase > aaveBalance` 이면 throw (프론트 우회 방지)

**변경 파일**
- `web/src/components/modals/OpenPositionPreviewModal.tsx`

**왜 그렇게 했는지**
- approve 문제가 아닌 supplyAmount 계산 문제 — approve 로직은 그대로 유지
- `Number()` 기반 float 연산은 bigint 정밀도 손실 → viem `formatUnits` + 문자열 처리로 안전하게
- UI는 기존 레이아웃 유지, 에러 표시만 추가

**남은 문제**
- 없음

---

## 2026-05-01 tx revert 무시 버그 수정 ✓

**현상**
- openPosition / closePosition / collectFees 트랜잭션이 on-chain에서 revert돼도 "COMPLETED" alert가 뜸

**원인**
`waitForTransactionReceipt` 는 revert된 tx도 정상 반환함 (`status: "reverted"`).
코드에서 `receipt.status` 를 확인하지 않아 revert 여부와 관계없이 성공 처리됨.
approve 단계는 `waitForTransactionReceipt` 자체가 없었음.

**수정**
- `OpenPositionPreviewModal` — approve에 `waitForTransactionReceipt` 추가. openPosition/approve 모두 `receipt.status === "reverted"` 이면 throw. catch에서 `txError` 상태 세팅 → 모달 내 빨간 텍스트 표시
- `ClosePositionPreviewModal` — 동일 패턴 적용
- `UniswapPositionCard` — collectFees revert 시 throw → `CollectFeesModal`의 기존 `setError`로 표시

에러 메시지는 viem의 `shortMessage` 우선, 없으면 `message` 사용.

---

## 2026-05-01 포지션 안 보이는 버그 수정 ✓

**현상**
- openPosition tx 성공 후에도 Strategy overview, Your Uniswap LP 모두 빈 상태

**원인**
`userPositionIds(address, index)` 는 유저의 포지션 배열을 인덱스로 순회하는 구조.  
두 훅 모두 `length: 5` 로 인덱스 0~4만 스캔했는데, 실제 오픈 포지션이 인덱스 5, 6에 있었음.  
배열 범위를 벗어난 인덱스는 revert → `allowFailure: true` 로 `0n` 처리 → 필터아웃.

RPC 직접 호출 결과 (0x7a227... 기준):

| index | tokenId | isOpen |
|-------|---------|--------|
| 0~4   | 20868~20890 | false |
| 5     | 20891   | **true** |
| 6     | 27443   | **true** |

**수정**
- `useStrategyPositionView.ts` — `Array.from({ length: 5 })` → `length: 20`
- `useUserUniPositions.ts` — `MAX_POSITIONS = 5` → `20`

범위를 벗어난 인덱스는 allowFailure로 자동 필터링되므로 사이드이펙트 없음.

**교훈**
포지션을 여러 번 열고 닫으면 배열 인덱스가 쌓인다. 스캔 범위는 실제 사용 패턴보다 넉넉하게 잡아야 함.

---

## 2026-05-01 tx hint 연동 (1-5) ✓

- 작업 목적
  - 사용자가 wallet tx 제출 후 txHash를 받으면 `POST /api/tx-hints`로 pending 상태를 백엔드에 기록
  - 기존 wallet transaction flow를 깨지 않는 보조 호출로 처리
- 읽은 파일
  - `api-spec.md`, `docs/backend/decisions.md`, `docs/frontend/backend-integration-plan.md`
  - `web/src/lib/backendApi.ts`
  - `web/src/components/modals/OpenPositionPreviewModal.tsx`
  - `web/src/components/modals/ClosePositionPreviewModal.tsx`
  - `web/src/components/modals/CollectFeesModal.tsx`
  - `web/src/components/dashboard/UniswapPositionCard.tsx`
- 변경한 파일
  - `web/src/lib/backendApi.ts` — `TxActionType`, `postTxHint(req)` 추가
  - `web/src/components/modals/OpenPositionPreviewModal.tsx` — `openPosition` txHash 직후 hint 호출
  - `web/src/components/modals/ClosePositionPreviewModal.tsx` — `closePosition` hash 직후 hint 호출
  - `web/src/components/dashboard/UniswapPositionCard.tsx` — `useAccount` 추가, `collectFees` hash 직후 hint 호출
- actionType 매핑
  - `openPosition` → `OPEN_POSITION`
  - `closePosition` → `CLOSE_POSITION`
  - `collectFees` → `COLLECT_FEES`
- 왜 그렇게 했는지
  - `writeContractAsync` 반환값이 txHash이고 이 시점이 broadcast 성공 직후 (서명만은 아님)
  - `.catch()` fire-and-forget으로 hint 실패가 메인 flow를 막지 않게 처리
  - CollectFeesModal은 콜백 패턴이라 실제 tx 실행부(`handleExecuteCollect`)가 UniswapPositionCard에 있으므로 거기에서 호출
  - Approve tx는 hint 대상 아님 (포지션 액션이 아닌 ERC20 허용)
- 남은 문제
  - approve tx에 대한 hint는 현재 의도적으로 제외 (포지션 상태 변경과 무관)

---

## 2026-05-01 Position activity 섹션 연동 (1-4) ✓

- 변경한 파일
  - `web/src/lib/backendApi.ts` — `UserPosition`, `TimelineItem` 타입 + `fetchUserOpenPositions`, `fetchPositionTimeline` 함수 추가
  - `web/src/components/dashboard/strategy/PositionActivitySection.tsx` (신규) — 지갑 주소 기준 포지션 → 타임라인 2-step 조회
  - `web/src/app/page.tsx` — `StrategyPositionCard` 아래에 `PositionActivitySection` 추가
- 동작
  - wallet 미연결: "Connect wallet" 안내
  - 오픈 포지션 없음: empty state
  - 오픈 포지션 있으면 첫 번째 tokenId 기준 timeline 표시
  - metadata JSON string: try/catch로 파싱 후 주요 필드(supplyAmount, borrowedAmount, spent0, spent1, amount0, amount1) 표시
  - wei → formatUnits(BigInt, 18) 변환 후 소수점 2~4자리 표시
  - eventType별 색상 배지 (OPENED, CLOSED, LIQUIDITY_ADDED, FEES_COLLECTED 등)
- 트러블슈팅
  - wagmi 체크섬 주소 → 백엔드 소문자 불일치: fetchUserOpenPositions에서 `.toLowerCase()` 적용으로 해결

---

## 2026-05-01 useHookEventStore 정리 (dead write 제거)

- 작업 목적
  - HookEventSection이 store를 더 이상 읽지 않아 store 전체가 write-only 상태가 된 것을 정리
- 읽은 파일
  - `web/src/components/modals/OpenPositionPreviewModal.tsx`
  - `web/src/components/modals/ClosePositionPreviewModal.tsx`
  - `web/src/components/modals/DemoTraderModal.tsx`
- 변경한 파일
  - `web/src/components/modals/OpenPositionPreviewModal.tsx` — store import, HOOK_ADDRESS, addManyHookEvents, 이벤트 수집 블록 제거 / hookAbi·decodeEventLog import 제거
  - `web/src/components/modals/ClosePositionPreviewModal.tsx` — 동일
  - `web/src/components/modals/DemoTraderModal.tsx` — store import, UiHookEvent 타입, uiEvents 생성 블록 제거
  - `web/src/store/useHookEventStore.ts` — 파일 삭제
- 왜 그렇게 했는지
  - store가 write-only가 된 시점에 dead code가 되므로, 남기면 혼란만 생김
  - DemoTrader 결과는 백엔드에서 event-sync로 이미 수집되므로 프론트에서 별도 저장 불필요
- 남은 문제
  - 없음

---

## 2026-05-01 Swap & price events 백엔드 API 연동 ✓

- 변경한 파일
  - `web/src/lib/backendApi.ts` (신규) — `fetchPriceEvents(poolId, limit)` fetch 클라이언트
  - `web/src/components/dashboard/HookEventSection.tsx` — Zustand 제거, `useQuery` + SVG sparkline (tick 기준, 라이브러리 없음)
  - `web/.env.local` — `NEXT_PUBLIC_BACKEND_URL`, `NEXT_PUBLIC_POOL_ID` 추가
  - `web/src/store/useHookEventStore.ts` — 삭제 (write-only가 된 store 제거)
  - `OpenPositionPreviewModal`, `ClosePositionPreviewModal`, `DemoTraderModal` — store 의존 제거
- 결과
  - `GET /api/pools/{poolId}/price-events` 연동 성공 (2026-05-01 확인)
  - CORS는 백엔드 `APP_CORS_ALLOWED_ORIGINS` 설정으로 해결

---

## 2026-05-01 백엔드 연동 계획 수립 (구조 분석)

- 작업 목적
  - 백엔드 4개 API를 기존 프론트에 연결하기 위한 파일 단위 계획 수립
- 읽은 파일
  - `api-spec.md`, `docs/backend/decisions.md`
  - `web/src/app/page.tsx`
  - `web/src/components/dashboard/HookEventSection.tsx`
  - `web/src/components/dashboard/strategy/StrategyPositionCard.tsx`
  - `web/src/components/dashboard/UniswapPositionCard.tsx`
  - `web/src/components/modals/DemoTraderModal.tsx`
  - `web/src/store/useHookEventStore.ts`
  - `web/src/hooks/useStrategyPositionView.ts`
  - `web/src/config/contracts.ts`, `web/src/lib/contracts.ts`
  - `web/.env.local`
- 변경한 파일
  - `docs/frontend/backend-integration-plan.md` (신규 작성)
  - `docs/agent-logs/frontend.md`
- 한 일
  - web/ 전체 파일 구조와 각 컴포넌트 데이터 흐름 파악
  - 4개 API를 기존 컴포넌트와 매핑 (어디에 붙일지 결정)
  - 신규/수정 파일 목록과 env 변수 계획 문서화
- 왜 그렇게 했는지
  - 기존 on-chain 데이터 흐름을 깨지 않으면서 백엔드를 보조 소스로 추가하는 방향이 최소 변경
  - price events: Zustand store에 addMany로 주입 → HookEventSection UI 변경 불필요
  - strategy positions: on-chain view가 더 풍부하므로 대체하지 않고 timeline만 추가
  - all positions: 기존에 없던 섹션이므로 신규 컴포넌트로 추가
- 남은 문제
  - `.env.local`에 `NEXT_PUBLIC_BACKEND_URL`, `NEXT_PUBLIC_POOL_ID` 추가 필요
  - 백엔드 CORS 설정에서 `http://localhost:3000` 허용 확인 필요
  - `timeline.metadata` JSON string 파싱: try/catch 처리 예정

---

## 2026-05-01 API 응답 예시 문서 정리

- 작업 목적
  - 프론트가 바로 참고할 수 있게 조회 API 문서를 실제 응답 기준으로 정리
- 읽은 파일
  - `api-spec.md`
  - `docs/backend/decisions.md`
- 변경한 파일
  - `api-spec.md`
  - `docs/agent-logs/frontend.md`
- 한 일
  - 로컬 서버를 실제로 띄워서 `positions/open`, `users/{userAddress}/positions/open`, `positions/{tokenId}/timeline`, `pools/{poolId}/price-events` 응답 JSON을 다시 수집
  - `api-spec.md`의 조회 API 예시를 실제 응답 값 기준으로 교체
  - 문서와 실제 구현이 달랐던 `cursor` query, `ownerAddress`/`vaultAddress` 필터, `timeline.metadata` 타입을 현재 구현 기준으로 수정
- 왜 그렇게 했는지
  - 프론트는 draft 예시보다 실제 응답 shape를 보고 붙이는 게 안전해서
- 남은 문제
  - `timeline.metadata`가 현재 JSON string이라 프론트에서 한 번 더 파싱해야 함
  - `nextCursor`는 현재 응답에 있지만 pagination 용도로는 쓰지 않음
