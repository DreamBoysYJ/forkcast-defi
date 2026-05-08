# QA Test Scenarios

> 2026-05-04 기준 실제 로컬 실행 검증 결과를 반영해 보강했다.
> 테스트 코드 작성 전 수동 검증 기준 문서로 사용한다.

---

## 검증 상태 범례

- ✅ 로컬에서 직접 확인 완료
- ⚠️ 동작하지만 스펙/설계와 차이 있음
- ❌ 미구현 또는 버그
- 📝 아직 확인 안 됨

---

## 1. 외부 조회 API 검증

### 1-1. 전체 오픈 포지션 조회 ✅

Given:
- `event-sync`가 성공해서 `strategy_position`에 오픈 포지션 데이터가 있다

When:
- `GET /api/positions/open?limit=20` 호출

Then:
- `isOpen=true` 인 포지션만 내려온다
- `tokenId`, `ownerAddress`, `vaultAddress`, `openedBlock`, `openedTxHash`가 DB와 일치한다
- 정렬은 최신 `openedBlock` 기준 내림차순이다

검증 결과 (2026-05-04):
- tokenId=27443 (실제 체인), tokenId=990001 (더미), tokenId=20891 (실제 체인) 3건 확인
- 정렬 기준 최신 openedBlock 내림차순 확인

---

### 1-2. 유저별 오픈 포지션 조회 ✅

Given:
- 특정 `owner_address`를 가진 오픈 포지션이 존재한다

When:
- `GET /api/users/{userAddress}/positions/open?limit=20` 호출

Then:
- 해당 유저의 오픈 포지션만 내려온다
- 다른 유저 포지션은 포함되지 않는다

검증 결과 (2026-05-04):
- `0x7a227d...` 주소 → tokenId=20891, tokenId=27443 반환 (다른 주소 포함 안 됨)
- `0x9cf7b6...` 주소 → tokenId=990001 반환

주의: 프론트는 wagmi address (체크섬 주소)를 toLowerCase()로 변환 후 호출해야 함 (backendApi.ts에서 처리 중)

---

### 1-3. 포지션 타임라인 조회 ✅

Given:
- `position_timeline`에 `OPENED`, `FEES_COLLECTED`, `CLOSED` 이벤트가 적재돼 있다

When:
- `GET /api/positions/{tokenId}/timeline?limit=20` 호출

Then:
- 해당 `tokenId` 이벤트만 내려온다
- `eventType`, `txHash`, `blockNumber`, `metadata`가 DB와 일치한다
- 정렬은 최신 이벤트 기준 내림차순이다

검증 결과 (2026-05-04):
- tokenId=20891: FEES_COLLECTED 2건 + OPENED 1건 (3건, 최신순) 확인
- tokenId=27443: OPENED 1건 (실제 체인 이벤트) 확인
- `metadata`는 JSON string이므로 프론트에서 try/catch로 파싱 필요

⚠️ 주의 사항:
- `eventTimestamp`는 block timestamp가 아닌 sync 시각 (`Instant.now()`)
- 더미 데이터와 실제 체인 이벤트의 `metadata` 필드 구조가 다를 수 있음
  - 더미: `{"amount0": "...", "amount1": "..."}`
  - 실제 FEES_COLLECTED: `{"token0": "0x...", "token1": "0x...", "amount0": "...", "amount1": "..."}`

---

### 1-4. 풀 가격 이벤트 조회 ✅

Given:
- `pool_price_event`에 특정 `pool_id` 이벤트가 적재돼 있다

When:
- `GET /api/pools/{poolId}/price-events?limit=20` 호출

Then:
- 해당 풀 이벤트만 내려온다
- `tick`, `sqrtPriceX96`, `txHash`, `blockNumber`가 DB와 일치한다
- 정렬은 최신 이벤트 기준 내림차순이다

검증 결과 (2026-05-04):
- poolId `0x26ac4021...` 기준 tick=1215 최신 이벤트 포함 7건 이상 반환 확인
- 실제 체인 이벤트 (txHash `0x094cc...`) 포함

⚠️ `eventTimestamp`는 sync 시각이며 block timestamp가 아님

---

### 1-5. 포지션 스냅샷 조회 ✅

Given:
- snapshot job이 성공해서 `position_snapshot`에 데이터가 있다

When:
- `GET /api/positions/{tokenId}/snapshots?limit=20` 호출

Then:
- 해당 tokenId 스냅샷이 최신순으로 내려온다
- `liquidity`, `amount0Now`, `amount1Now`, `healthFactor` 등이 string으로 내려온다
- `healthFactor`가 sentinel 최대값인 경우 프론트에서 "No Debt" 처리 필요

검증 결과 (2026-05-04):
- tokenId=990001 (더미 vault): `liquidity=0`, `healthFactor=99999999...` — sentinel 정상 처리
- tokenId=20891 (실제 체인): `liquidity=23742862691659053238`, `healthFactor=1.319...` — 실제 온체인 값
- tokenId=27443 (실제 체인): `liquidity=180443281420510838654`, `healthFactor=1.319...` — 실제 온체인 값

⚠️ 주의: tokenId=20891과 tokenId=27443가 같은 vault를 공유해서 healthFactor가 동일하게 보임 (account-level HF)

---

### 1-6. tx-hint 저장 ✅

Given:
- 프론트에서 txHash, actionType, userAddress를 포함한 요청 전송

When:
- `POST /api/tx-hints` 호출

Then:
- `202 ACCEPTED` + `{"status":"ACCEPTED","txHash":"..."}` 반환
- 중복 txHash 요청 시 `400 BAD_REQUEST` 반환

검증 결과 (2026-05-04):
- 신규 hint 저장 ✅
- 중복 txHash 거부 ✅
- missing 필드 시 400 validation error ✅

---

## 2. error/edge case 검증

### 2-1. 존재하지 않는 tokenId 조회 ✅

Given:
- tokenId=999999는 DB에 없다

When:
- `GET /api/positions/999999/timeline?limit=20` 호출
- `GET /api/positions/999999/snapshots?limit=20` 호출

Expected (current v1 policy):
- 200 OK `{"items":[],"nextCursor":null}`

Actual:
- 200 OK `{"items":[],"nextCursor":null}`

---

### 2-2. 잘못된 userAddress 조회 ✅

Given:
- `invalid_addr`는 Ethereum 주소 형식이 아니다

When:
- `GET /api/users/invalid_addr/positions/open?limit=20` 호출

Expected (current v1 policy):
- 200 OK `{"items":[],"nextCursor":null}`

Actual:
- 200 OK `{"items":[],"nextCursor":null}`

---

### 2-3. 잘못된 poolId 조회 ✅

Given:
- `not_a_pool_id`는 풀 ID 형식이 아니다

When:
- `GET /api/pools/not_a_pool_id/price-events?limit=5` 호출

Expected (current v1 policy):
- 200 OK `{"items":[],"nextCursor":null}`

Actual:
- 200 OK `{"items":[],"nextCursor":null}`

Decision (2026-05-04):
- v1 조회 API는 결과가 없거나 identifier 형식을 엄격히 검증하지 않는 경우에도 empty list 응답으로 다룬다
- QA는 이를 B3 버그로 재오픈하지 말고, 현재 API 정책으로 본다

---

## 3. event-sync 검증

### 3-1. event-sync 신규 이벤트 처리 ✅

Given:
- cursor가 있고 그 이후 블록에 PositionOpened, SwapPriceLogged 이벤트가 있다

When:
- `POST /internal/jobs/event-sync` 호출

Then:
- `raw_chain_event`에 저장
- `strategy_position` 업데이트 (PositionOpened)
- `position_timeline` 업데이트 (appendOpened)
- `pool_price_event` 업데이트 (SwapPriceLogged)
- `sync_cursor` 전진
- `job_run` 성공 기록

검증 결과 (2026-05-04):
- 블록 10766883–10786605 범위에서 2건 처리 (PositionOpened tokenId=27443 + SwapPriceLogged)
- cursor 10786617까지 정상 전진

---

### 3-2. event-sync 중복 이벤트 무시 ✅

Given:
- 이미 처리된 `(tx_hash, log_index)` 이벤트가 다시 들어온다

When:
- event-sync가 동일 블록 범위를 재처리한다

Then:
- `raw_chain_event` unique constraint로 중복 insert 막힘
- `saveIfAbsent()` → false 반환 → read model 업데이트 skip

---

### 3-3. job lock으로 동시 실행 방지 + 정상 종료 후 즉시 해제 ✅

Given:
- event-sync job이 실행 중이다 (lock 보유)

When:
- 두 번째 `POST /internal/jobs/event-sync` 호출

Then:
- `202 SKIPPED` + `{"status":"SKIPPED","reason":"already running"}` 반환

Given:
- event-sync job이 완료됐다 (finally에서 lock release)

When:
- 즉시 다시 `POST /internal/jobs/event-sync` 호출

Then:
- lock 획득 성공 → job 재실행

검증 결과 (2026-05-04, 서버 재시작 후):
- 1차 성공 후 즉시 2차 호출 → `"reason":"no finalized block range"` (lock 획득 성공, 처리할 블록 없어서 SKIPPED)
- 3차 호출 → SUCCESS (lock 재획득 성공)
- snapshot 연속 2회 → SUCCESS + SUCCESS
- **B1 수정 확인됨**: `JobLockService.release()` + `EventSyncService/SnapshotService`의 `finally` block 작동 정상

---

### 3-4. cursor 없는 상태에서 bootstrap 처리 ✅

Given:
- `sync_cursor` DB row가 없다

When:
- event-sync 첫 실행

Then:
- `safeHead - bootstrapWindowBlocks` 근처에서 cursor 초기화
- 전체 체인 genesis부터 스캔하지 않음

---

## 4. snapshot job 검증

### 4-1. snapshot job 정상 실행 ✅

Given:
- `strategy_position`에 `is_open=true` 포지션이 있다

When:
- `POST /internal/jobs/snapshot` 호출

Then:
- 오픈 포지션 각각에 대해 StrategyLens 호출
- `position_snapshot` 저장 (`snapshot_at`, `observed_block_number` 포함)
- `job_run` 성공 기록

검증 결과 (2026-05-04):
- 3개 포지션 (990001, 20891, 27443) 스냅샷 성공

---

### 4-2. sentinel healthFactor 처리 ✅

Given:
- StrategyLens가 no-debt 포지션에 `uint256 max`를 반환한다

When:
- snapshot job이 해당 포지션 저장 시도

Then:
- `healthFactor`는 `99999999999999999999.999999999999999999`으로 요약 저장 (DB 저장 가능한 최대 finite 값)
- job 전체가 실패하지 않음

검증 결과 (2026-05-04):
- tokenId=990001 (dummy, no-debt): `healthFactor=99999999999999999999.999999999999999999` 확인
- 프론트에서 이 값은 `isNoDebt()` 헬퍼로 "No Debt" 표시

---

### 4-3. 더미 포지션 snapshot 문제 📝

Given:
- tokenId=990001의 vault address (`0xb88fff9...`)는 실제 체인에 존재하지 않는 더미 주소다

When:
- snapshot job이 StrategyLens를 해당 vault로 호출

Then:
- `liquidity=0`, `amount0Now=0`, `amount1Now=0`, `totalCollateralBase=0`, `totalDebtBase=0`
- `healthFactor=sentinel 최대값`

실제로 확인된 현상:
- 더미 vault에 대해 StrategyLens가 0/sentinel을 반환하고 있음
- 이 값이 DB에 저장되어 프론트에 0으로 표시될 수 있음
- 프로덕션에는 이 더미 데이터가 없으므로 직접 문제는 없음
- 로컬 환경에서 `tokenId=990001`을 테스트할 때 실제 포지션과 혼동 주의

---

## 5. pending_tx 검증

### 5-1. tx-hint 저장 ✅

Given:
- `txHash`, `actionType`, `userAddress` 모두 유효하다

When:
- `POST /api/tx-hints` 호출

Then:
- `202 ACCEPTED` + `{"status":"ACCEPTED","txHash":"..."}`
- `pending_tx` 테이블에 `PENDING` 상태로 저장

---

### 5-2. pending_tx 상태 reconcile 📝 (v1 scope out)

Given:
- 프론트가 txHash를 hint로 저장했다
- 그 txHash에 해당하는 on-chain 이벤트가 event-sync로 수집됐다

When:
- event-sync가 해당 이벤트를 처리한다

Expected:
- v1 현재 기준으로는 별도 상태 변화가 없어도 된다
- `pending_tx`는 frontend tx submission 기록으로만 남고, 최종 truth는 on-chain / read model 기준으로 판단한다

Actual:
- `EventSyncService`에 reconcile 로직 없음
- `PendingTxService`에 `markConfirmed()` 등 메서드 있으나 호출하는 곳 없음
- `pending_tx`는 생성 후 status가 `PENDING`으로 유지된다

Decision (2026-05-04):
- 이 항목은 v1에서 의도적으로 scope out 한다
- QA는 이를 신규 버그로 재오픈하지 말고, `known limitation / future work`로 취급한다
- `pending_tx`는 현재 pending UX용 실시간 상태머신이 아니라 기록용에 가깝다

---

## 6. 프론트-백엔드 연동 검증

### 6-1. backendApi.ts 타입 정합성 ✅

- `PriceEventItem`, `UserPosition`, `TimelineItem`, `SnapshotItem` 타입이 실제 API 응답과 일치 확인
- `SnapshotItem.healthFactor: string` — BigDecimal을 string으로 처리 ✅
- `TimelineItem.metadata: string` — JSON string으로 처리, try/catch 파싱 ✅

### 6-2. wagmi 주소 소문자 변환 ✅

- wagmi가 체크섬 주소를 반환하는 경우 백엔드 DB 주소와 불일치
- `fetchUserOpenPositions`에서 `.toLowerCase()` 적용으로 해결됨

### 6-3. CORS ✅

- `http://localhost:3000` Origin에 대해 `Access-Control-Allow-Origin` 정상 응답
- OPTIONS preflight 200 확인

---

## 7. 미확인 / 추후 검증 항목

| 항목 | 설명 | 우선순위 |
|------|------|---------|
| `event_timestamp` block timestamp 교체 | 초기에는 ingest 경로 완성을 우선해 sync 시각 사용. 정확한 chain 시각이 중요해지면 이후 개선 | MEDIUM |
| `pending_tx` reconcile 구현 | v1에서는 보류. pending UX 또는 상태 조회 API가 실제로 필요해질 때 재검토 | LOW |
| job lock release 재확인 | 수정 후 서버 재시작/재배포 환경에서 계속 정상 동작하는지 확인 | LOW |
| stricter 4xx validation | 필요해지면 이후 버전에서 추가 검토 | LOW |
| tx-hint duplicate response policy | current v1 policy is 400 BAD_REQUEST | LOW |
| 프론트 UI 실제 브라우저 검증 | 새 포지션 27443 노출 여부 확인 | MEDIUM |

---

## 8. 검증에 사용한 데이터 현황 (2026-05-04)

| tokenId | 상태 | 데이터 출처 | 비고 |
|---------|------|------------|------|
| 20891 | isOpen=true | 실제 체인 (Sepolia) | OPENED block 9715930, FEES_COLLECTED 더미 2건 혼재 |
| 27443 | isOpen=false | 실제 체인 (Sepolia) | OPENED block 10767041, CLOSED block 10786802, timeline 최신 이벤트 CLOSED 확인 |
| 990001 | isOpen=true | DB 시드 더미 | vault 없음, snapshot 0값, 로컬 테스트용 |

sync cursor 현황:
- `event-sync-finalized`: 마지막 확인 시 `10786617` (2026-05-04 기준)
