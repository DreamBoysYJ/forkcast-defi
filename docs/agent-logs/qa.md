# QA Agent Log

## 2026-05-04 통합 검증 세션

### 작업 목적

- 현재 구현 상태(백엔드/프론트 연동)를 문서와 로그를 기준으로 스스로 파악
- 실제 API 호출 및 job 실행으로 검증
- test-scenarios.md 보강
- gap / 버그 정리

### 읽은 파일

- `AGENTS.md`, `api-spec.md`
- `docs/backend/data-model.md`, `docs/backend/scheduler-plan.md`, `docs/backend/decisions.md`
- `docs/frontend/backend-integration-plan.md`
- `docs/agent-logs/backend-review.md`, `docs/agent-logs/frontend.md`, `docs/agent-logs/ops.md`
- `docs/qa/test-scenarios.md`, `docs/agent-logs/qa.md`
- `backend/src/.../EventSyncService.java`
- `backend/src/.../SnapshotService.java`
- `backend/src/.../JobLockService.java`
- `backend/src/.../PositionTimelineService.java`
- `backend/src/.../RawChainEventService.java`
- `backend/src/.../EventLogDecoder.java`
- `backend/src/.../PendingTxService.java`
- `web/src/lib/backendApi.ts`

### 변경한 파일

- `docs/qa/test-scenarios.md` (전면 보강)
- `docs/agent-logs/qa.md`

### 실행한 검증

1. **백엔드 서버 응답 확인**: `localhost:8080` 정상 동작
2. **CORS**: `http://localhost:3000` Origin 허용 확인 (OPTIONS 200, Access-Control-Allow-Origin 정상)
3. **모든 외부 조회 API 호출**:
   - `GET /api/positions/open` → 3건 (27443, 990001, 20891)
   - `GET /api/users/0x7a227d.../positions/open` → 2건 (20891, 27443)
   - `GET /api/positions/20891/timeline` → 3건 (FEES_COLLECTED×2, OPENED)
   - `GET /api/positions/990001/snapshots` → 3건 (sentinel healthFactor 확인)
   - `GET /api/pools/{poolId}/price-events` → 7건 이상
4. **job 직접 실행**:
   - `POST /internal/jobs/event-sync` → SUCCESS, processedEvents=2, cursor 10786605
     - 신규 발견: tokenId=27443 PositionOpened + SwapPriceLogged (실제 체인 이벤트)
   - `POST /internal/jobs/snapshot` → SUCCESS, 3 positions snapshotted
5. **연속 실행 테스트**: 20초 후 재실행 → SKIPPED "already running" (lock 미해제 버그 확인)
6. **error case 테스트**:
   - non-existent tokenId → 200 빈 배열 (스펙: 404)
   - invalid userAddress → 200 빈 배열 (스펙: 400)
   - invalid poolId → 200 빈 배열 (스펙: 400)
7. **tx-hint 테스트**:
   - 신규 hint → 202 ACCEPTED
   - 중복 hint → 400 BAD_REQUEST
8. **코드 리뷰**: EventSyncService, SnapshotService, PendingTxService, PositionTimelineService

### 확인된 사실 (Fact)

- **event-sync E2E 동작**: 블록 범위 스캔 → raw_chain_event 저장 → read model(strategy_position, position_timeline, pool_price_event) 업데이트 → cursor 전진 → job_run 기록 모두 정상
- **snapshot E2E 동작**: open positions 조회 → StrategyLens call → position_snapshot 저장 → job_run 기록 모두 정상
- **idempotency**: (tx_hash, log_index) unique constraint로 중복 이벤트 저장 차단 확인
- **sentinel healthFactor**: no-debt 포지션에서 `99999999...` 저장, 프론트 "No Debt" 처리 정상
- **더미 포지션 990001**: vault 없음으로 StrategyLens가 0값 반환 → snapshot에 0 저장 (예상된 동작)
- **tokenId=20891, 27443이 같은 healthFactor 공유**: 동일 vault address 사용, StrategyLens account-level HF 반환
- **backendApi.ts 타입 정합성**: 실제 API 응답과 타입 일치 확인
- **frontend address 소문자 변환**: wagmi 체크섬 주소 → `.toLowerCase()` 처리 backendApi.ts에서 완료

### 발견된 버그/Gap

| 번호 | 분류 | 설명 | 심각도 |
|------|------|------|--------|
| B1 | 버그 | job lock이 완료 후에도 해제 안 됨 (2분 lease 만료까지 SKIPPED) | HIGH |
| B2 | API policy | tx-hint 중복은 v1에서 400 BAD_REQUEST로 처리 | LOW |
| B3 | API policy | 조회 결과 없음 / 느슨한 identifier 처리 시 200 빈 배열 반환. v1 정책으로 수용 | LOW |
| B4 | Known debt | event_timestamp는 초기 ingest 경로 완성을 우선하기 위해 sync 시각을 사용. block timestamp 정밀도는 이후 개선 대상 | MEDIUM |
| B5 | Known limitation | pending_tx reconcile 없음. v1에서는 기록용으로 두고, QA 재오픈 대상 버그로 보지 않음 | LOW |
| B6 | 데이터 혼재 | FEES_COLLECTED metadata 형태: 더미(amount0/1만) vs 실제(token0/1/amount0/1) | LOW |

### 추정/미확인 항목

- 프론트 브라우저에서 닫힌 tokenId=27443가 open 기반 섹션에서 제거된 것 외에, 별도 closed history UI가 필요한지는 미확인
- Cloud Scheduler 실제 인증 흐름 미검증 (local dev SCHEDULER_AUTH_ENABLED=false)

### 왜 그렇게 했는지

- 문서만으로는 실제 상태 파악 불가 → 직접 API 호출로 확인
- job 재실행으로 실제 체인 이벤트가 새로 들어오는지 검증 → 27443 신규 확인
- 코드 레벨 리뷰로 lock 미해제, pending_tx reconcile 누락을 확인
- 더미 데이터가 프로덕션에는 없는 데이터이지만 로컬 검증에 영향을 주므로 별도 명시

### 남은 문제

- B1 job lock release → 코드는 반영됨 (`finally { jobLockService.release() }`), 서버 재시작 후 재검증 필요
- B5 pending_tx reconcile → 2026-05-04 기준 v1 scope out. pending UX 또는 상태 조회 API가 실제 요구될 때 재검토
- B3 200 empty 정책 → 2026-05-04 기준 v1 조회 정책으로 수용. stricter 4xx validation은 이후 버전에서 재검토
- 더미 포지션 990001 cleanup → 프로덕션 배포 전 확인 필요

---

## 2026-05-04 B1 재검증 (서버 재시작 후)

### 작업 목적

- B1(job lock 미해제) 수정 코드 반영 + 서버 재시작 후 재검증

### 읽은 파일

- `docs/agent-logs/backend-review.md` (B1 수정 내용 확인)
- `backend/src/.../JobLockService.java` (release 메서드 추가 확인)
- `backend/src/.../JobLock.java` (releaseAt 메서드 추가 확인)
- `backend/src/.../EventSyncService.java` (finally block 확인)

### 실행한 검증

1. 서버 재시작 전: lock 만료 기다린 뒤 1차 SUCCESS → 즉시 2차 → SKIPPED (구 코드 확인)
2. 서버 재시작 후: lock 만료 기다린 뒤 1차 SUCCESS → 즉시 2차 → `"reason":"no finalized block range"` ← 이것이 새 동작
3. 3차 실행 → SUCCESS
4. snapshot 연속 2회: SUCCESS + SUCCESS
5. 실제 close tx 후 `POST /internal/jobs/event-sync` 실행
6. DB 확인:
   - `raw_chain_event` 최신 이벤트에 `PositionClosed` 저장 확인
   - `strategy_position.token_id=27443` → `is_open=false`, `closed_block=10786802`, `closed_tx_hash` 반영 확인
7. API 확인:
   - `GET /api/positions/27443/timeline?limit=20` → 최신 이벤트 `CLOSED` 확인
8. 프론트 화면 확인:
   - `View all positions`에서 27443 제거 확인
   - open position 기반 activity 섹션에서도 27443 미노출 확인

### 확인된 사실

- B1 **수정 확인** ✅
- 새 동작: job 완료 직후 재실행 시 `"already running"` 대신 `"no finalized block range"` 또는 SUCCESS
  - `"no finalized block range"`: lock 획득 성공, 처리할 새 블록 없음 → 정상 SKIPPED
  - SUCCESS: lock 획득 성공, 새 블록 있으면 정상 처리
- `EventSyncService`/`SnapshotService` 모두 `finally { jobLockService.release(JOB_NAME) }` 정상 실행

### 남은 문제

- 없음 (B1 검증 완료)

---

## 2026-04-30 조회 API 검증 시작

- 작업 목적
  - event-sync 이후 조회 API가 실제 DB 적재 결과와 맞는지 검증 준비
- 읽은 파일
  - `api-spec.md`
  - `docs/backend/data-model.md`
  - `docs/backend/scheduler-plan.md`
  - `docs/backend/test-scenarios.md`
- 변경한 파일
  - `docs/qa/test-scenarios.md`
  - `docs/agent-logs/qa.md`
- 한 일
  - QA 시나리오 문서를 새로 만들고 현재 우선순위를 조회 API 검증 중심으로 정리
  - QA 로그 파일을 생성
- 왜 그렇게 했는지
  - 레포 가이드에 따라 QA 작업 전 시나리오 문서를 먼저 남기기 위해
- 남은 문제
  - 로컬 서버가 현재 응답하지 않아 API 실호출 검증이 아직 시작되지 않음

## 2026-04-30 조회 API 검증 완료

- 작업 목적
  - `event-sync` 이후 조회 API 3종이 실제 DB 결과와 맞는지 확인
- 읽은 파일
  - `backend/src/main/java/io/forkcast/backend/position/controller/OpenPositionController.java`
  - `backend/src/main/java/io/forkcast/backend/position/controller/PositionTimelineController.java`
  - `backend/src/main/java/io/forkcast/backend/pool/controller/PoolPriceEventController.java`
  - `backend/src/main/java/io/forkcast/backend/position/service/OpenPositionQueryService.java`
  - `backend/src/main/java/io/forkcast/backend/position/service/PositionTimelineQueryService.java`
  - `backend/src/main/java/io/forkcast/backend/pool/service/PoolPriceEventQueryService.java`
  - `backend/src/main/resources/application.yaml`
- 변경한 파일
  - `backend/src/main/java/io/forkcast/backend/position/controller/OpenPositionController.java`
  - `backend/src/main/java/io/forkcast/backend/position/controller/PositionTimelineController.java`
  - `backend/src/main/java/io/forkcast/backend/pool/controller/PoolPriceEventController.java`
  - `docs/agent-logs/qa.md`
- 한 일
  - 로컬 서버를 다시 띄워서 `GET /api/positions/open?limit=20` 호출 확인
  - 응답의 `tokenId=20891` 기준으로 `GET /api/positions/20891/timeline?limit=20` 호출 확인
  - `pool_id=0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c` 기준으로 `GET /api/pools/{poolId}/price-events?limit=20` 호출 확인
  - API 응답을 `strategy_position`, `position_timeline`, `pool_price_event` DB row와 직접 대조
  - 조회 API가 500 나던 원인을 찾아 컨트롤러의 null 응답 생성 방식과 `price-events` 경로 문자열을 최소 수정
- 왜 그렇게 했는지
  - 수동 검증을 진행하려면 먼저 실제로 호출 가능한 상태여야 했고, 수정 범위도 QA를 막는 부분만 최소로 제한하는 편이 맞다고 판단
- 남은 문제
  - `eventTimestamp`는 아직 체인 block timestamp가 아니라 동기화 시각 기준이라 실제 온체인 시각과 다를 수 있음
  - cursor 기반 pagination은 아직 구현되지 않아 `nextCursor`가 항상 null
