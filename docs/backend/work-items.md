# Backend Work Items

> 이 문서는 v1 백엔드 도입을 위한 작업 단위를 역할별로 정리한다.
> 기준 문서: `docs/backend/goal.md`, `docs/backend/data-model.md`, `docs/backend/scheduler-plan.md`, `docs/backend/decisions.md`, `api-spec.md`(루트), `docs/backend/test-scenarios.md`.
> 본 문서는 계획 문서이며, 코드 산출물의 완성도를 보증하지 않는다.

---

## 0. 사용 규칙

### 0-1. 역할 분배 원칙

- **Owner: User** — 사용자가 직접 구현하는 백엔드 작업. Claude는 리뷰어/질문 답변자 역할만 한다.
- **Owner: Claude (Frontend)** — 기존 v1 UI를 유지하면서 백엔드 API를 연결하는 작업. 디자인 임의 변경 금지.
- **Owner: Claude (QA)** — 시나리오/테스트 초안 작성. 실제 테스트 코드 작성은 별도 합의 후 수행.
- **Owner: Claude (Ops Docs)** — 운영용 문서 작성. 실제 인프라 적용은 사용자가 결정한다.

### 0-2. 항목 포맷

각 작업 항목은 다음을 포함한다.

- **Owner**: 책임 주체
- **선행 조건**: 시작하려면 끝나 있어야 하는 항목
- **산출물**: 결과물 형태 (코드, 문서, 마이그레이션 등)
- **완료 기준**: 어떤 상태가 되면 완료로 본다
- **참고**: 관련 문서/이슈/주의사항

### 0-3. 진행 상태 표기

각 항목 상단의 체크박스를 사용한다.

- `[ ]` 미시작
- `[~]` 진행 중
- `[x]` 완료
- `[!]` 보류/이슈

---

## A. 사용자 직접 백엔드 작업 (Owner: User)

> Claude는 이 섹션의 코드를 대량 생성하지 않는다.
> 사용자가 구현한 후 PR/리뷰 요청 시 Claude가 DB 정합성, unique, cursor, retry, job lock, 예외 처리 관점으로 리뷰한다.

---

### A1. Spring Boot 백엔드 모듈 생성

- [ ]
- **Owner**: User
- **선행 조건**: 없음
- **산출물**:
  - `backend/` 모듈 (디렉토리 명은 사용자 합의 시 변경 가능)
  - 패키지 구조 초안
  - Spring Boot 앱 부트스트랩 코드
- **완료 기준**:
  - 앱이 로컬에서 기동된다
  - `/actuator/health`가 200을 반환한다
- **참고**: Java 21, Spring Boot, Spring Web, Spring Data JPA, PostgreSQL 드라이버, Flyway, Actuator. CLAUDE.md에 따라 Claude는 코드 생성하지 않음.

---

### A2. 로컬 PostgreSQL 연결 설정

- [ ]
- **Owner**: User
- **선행 조건**: A1
- **산출물**:
  - `application-dev.yml` (또는 동등 설정)
  - 로컬 DB 기동 가이드 (docker-compose 또는 로컬 설치 안내)
- **완료 기준**:
  - dev 프로파일에서 백엔드가 PostgreSQL에 연결된다
  - Flyway가 빈 마이그레이션 상태에서 정상 동작한다
- **참고**: Cloud Run 배포 시 사용할 prod 프로파일 분리는 D2/Ops 문서에서 다룬다.

---

### A3. Flyway 초기 마이그레이션 (10개 테이블)

- [ ]
- **Owner**: User
- **선행 조건**: A2
- **산출물**:
  - `V1__init.sql` (또는 V1.x 분할)
  - 테이블: `sync_cursor`, `job_lock`, `job_run`, `pending_tx`, `raw_chain_event`, `strategy_position`, `position_timeline`, `pool_price_event`, `position_snapshot`, `user_vault`
- **완료 기준**:
  - 모든 테이블 생성
  - `data-model.md`와 `decisions.md`에 명시된 unique 제약 적용
    - `pending_tx.tx_hash`
    - `raw_chain_event(tx_hash, log_index)`
    - `pool_price_event(tx_hash, log_index)`
    - `user_vault.vault_address`
    - `position_snapshot(token_id, snapshot_at)`
  - timestamp 컬럼 (`updated_at`, `submitted_at`, `event_timestamp`, `snapshot_at` 등) 존재
  - v1에서는 FK 제약 미적용 (decisions.md §9)
- **참고**: 컬럼 타입은 사용자 결정. `payload_json`은 `jsonb` 권장 (decisions.md §4).

---

### A4. JPA 엔티티/리포지토리 (운영 + 힌트 테이블)

- [ ]
- **Owner**: User
- **선행 조건**: A3
- **산출물**:
  - `SyncCursor`, `JobLock`, `JobRun`, `PendingTx` 엔티티/리포지토리
- **완료 기준**:
  - 기본 CRUD 가능
  - unique 제약 위반 시 동작이 정의되어 있음 (예외 또는 upsert 정책 결정)

---

### A5. JPA 엔티티/리포지토리 (Read model + Snapshot + Raw event)

- [ ]
- **Owner**: User
- **선행 조건**: A4
- **산출물**:
  - `RawChainEvent`, `StrategyPosition`, `PositionTimeline`, `PoolPriceEvent`, `PositionSnapshot`, `UserVault` 엔티티/리포지토리
- **완료 기준**:
  - 기본 조회/삽입 가능
  - `payload_json`은 jsonb 매핑 (Hibernate UserType 또는 커스텀 컨버터)

---

### A6. Job lock 서비스

- [ ]
- **Owner**: User
- **선행 조건**: A4
- **산출물**:
  - lease 기반 lock 서비스 (acquire / release / heartbeat 또는 명시적 만료)
- **완료 기준**:
  - 락이 없으면 획득
  - `locked_until > now()`이면 skip
  - `locked_until < now()`이면 재획득 가능
  - 정상 종료 시 release
  - 동시성 테스트 시나리오 통과 (test-scenarios.md §3)

---

### A7. Job run 로깅 서비스

- [ ]
- **Owner**: User
- **선행 조건**: A4
- **산출물**:
  - 시작/종료/실패 시 `job_run` 레코드 작성 헬퍼
- **완료 기준**:
  - 성공/실패 모두 기록
  - `error_message`, `range_start_block`, `range_end_block` 채워짐

---

### A8. RPC 클라이언트 / 체인 로그 조회

- [ ]
- **Owner**: User
- **선행 조건**: A1
- **산출물**:
  - `eth_getLogs` 또는 동등 호출 래퍼
  - 주소/토픽/블록 범위 필터 지원
  - RPC 엔드포인트와 키는 외부화 (env)
- **완료 기준**:
  - 임의 블록 범위에 대해 Router/Hook 로그를 받아올 수 있다
  - 실패 시 명확한 예외 발생

---

### A9. 이벤트 디코딩

- [ ]
- **Owner**: User
- **선행 조건**: A8
- **산출물**:
  - 이벤트 디코더: `PositionOpened`, `PositionClosed`, `FeesCollected`, `SwapPriceLogged`
  - 디코딩 결과 도메인 객체
- **완료 기준**:
  - 각 이벤트 타입별 단위 테스트 통과
  - ABI/시그니처 출처 명시 (계약 코드 또는 ABI json 경로)

---

### A10. raw_chain_event 저장 (idempotent)

- [ ]
- **Owner**: User
- **선행 조건**: A5, A9
- **산출물**:
  - 로그 → `raw_chain_event` 삽입 서비스
- **완료 기준**:
  - `(tx_hash, log_index)` 중복은 무시 또는 안전 upsert
  - `payload_json`에 디코딩 필드 저장
  - `removed = true` 로그 처리 정책 결정 (decisions.md / test-scenarios.md §8-2 기준)

---

### A11. 프로젝션: Router 이벤트 → strategy_position / position_timeline / user_vault

- [ ]
- **Owner**: User
- **선행 조건**: A10
- **산출물**:
  - `PositionOpened` → `strategy_position` 신규/갱신 + `position_timeline.OPENED` + 필요 시 `user_vault` 보강
  - `PositionClosed` → `strategy_position.is_open=false`, closed 정보 갱신 + `position_timeline.CLOSED`
  - `FeesCollected` → `position_timeline.FEES_COLLECTED`
- **완료 기준**:
  - test-scenarios.md §4-1 ~ §4-3 모두 통과
  - 같은 raw 이벤트 재처리 시 read model이 깨지지 않음

---

### A12. 프로젝션: Hook 이벤트 → pool_price_event

- [ ]
- **Owner**: User
- **선행 조건**: A10
- **산출물**:
  - `SwapPriceLogged` → `pool_price_event` 삽입
- **완료 기준**:
  - test-scenarios.md §4-4 통과
  - `tick`, `sqrt_price_x96` 둘 다 저장 (decisions.md §5)
  - `pool_id` 저장 (decisions.md §6)

---

### A13. event-sync 엔드포인트 + 워크플로우

- [ ]
- **Owner**: User
- **선행 조건**: A6, A7, A10, A11, A12
- **산출물**:
  - `POST /internal/jobs/event-sync`
  - 락 획득 → cursor 로드 → 범위 결정 → fetch → raw 저장 → 프로젝션 → cursor 갱신 → job_run 기록 → 락 해제
- **완료 기준**:
  - 성공 시 `200`, 락 보유 중이면 `202 SKIPPED`
  - cursor는 성공 후에만 advance
  - api-spec.md §2-1과 응답 일치 (또는 변경 시 api-spec.md 동기화)
  - 인증 미적용 시 `401/403` (A22 완료 시 반영)

---

### A14. StrategyLens / view 호출 클라이언트

- [ ]
- **Owner**: User
- **선행 조건**: A8
- **산출물**:
  - `tokenId` → 현재 상태 (liquidity, amount0Now, amount1Now, currentTick, sqrtPriceX96, totalCollateralBase, totalDebtBase, healthFactor) 조회 함수
- **완료 기준**:
  - 단일 포지션에 대해 정상 응답 받음
  - 호출 실패 시 명확한 예외

---

### A15. snapshot 서비스

- [ ]
- **Owner**: User
- **선행 조건**: A5, A14
- **산출물**:
  - 오픈 포지션 조회 → lens 호출 → `position_snapshot` 삽입
- **완료 기준**:
  - test-scenarios.md §5-1, §5-2 통과
  - 부분 실패 정책이 코드와 문서에 일치 (기본: §5-3 권장안 = 전체 실패. 변경 시 decisions.md 업데이트)

---

### A16. snapshot 엔드포인트

- [ ]
- **Owner**: User
- **선행 조건**: A6, A7, A15
- **산출물**:
  - `POST /internal/jobs/snapshot`
- **완료 기준**:
  - api-spec.md §2-2와 응답 일치
  - 락/잡런 적용
  - 인증 미적용 시 `401/403`

---

### A17. 외부 API: 풀 가격 이벤트

- [ ]
- **Owner**: User
- **선행 조건**: A12
- **산출물**:
  - `GET /api/pools/{poolId}/price-events`
- **완료 기준**:
  - api-spec.md §1-1 응답 형태와 일치
  - cursor/limit 페이지네이션 동작
  - poolId 형식 검증

---

### A18. 외부 API: 내 오픈 포지션

- [ ]
- **Owner**: User
- **선행 조건**: A11
- **산출물**:
  - `GET /api/users/{userAddress}/positions/open`
- **완료 기준**:
  - api-spec.md §1-2와 일치
  - 사용자 주소 정규화 정책 결정 (lower-case 등)

---

### A19. 외부 API: 전체 오픈 포지션

- [ ]
- **Owner**: User
- **선행 조건**: A11
- **산출물**:
  - `GET /api/positions/open`
- **완료 기준**:
  - api-spec.md §1-3와 일치
  - `ownerAddress`, `vaultAddress` 옵션 필터 동작

---

### A20. 외부 API: 포지션 타임라인

- [ ]
- **Owner**: User
- **선행 조건**: A11
- **산출물**:
  - `GET /api/positions/{tokenId}/timeline`
- **완료 기준**:
  - api-spec.md §1-4와 일치
  - 알 수 없는 tokenId 처리는 test-scenarios.md §6-4 권장(`404`)에 따름. 다른 결정을 할 경우 문서 업데이트

---

### A21. 외부 API: 트랜잭션 힌트

- [ ]
- **Owner**: User
- **선행 조건**: A4
- **산출물**:
  - `POST /api/tx-hints`
- **완료 기준**:
  - 정상 시 `202 ACCEPTED` (api-spec.md §1-5)
  - 중복 `txHash` 처리 정책 결정 (test-scenarios.md §1-2: 멱등 성공 또는 `409`) 후 그대로 구현 + decisions.md에 기록

---

### A22. 내부 엔드포인트 인증 적용

- [ ]
- **Owner**: User
- **선행 조건**: A13, A16
- **산출물**:
  - `/internal/**` 보호 (OIDC + 시크릿 헤더 등 scheduler-plan §8)
- **완료 기준**:
  - 인증 미통과 시 `401` 또는 `403`
  - test-scenarios.md §7 통과

---

### A23. Dockerfile

- [ ]
- **Owner**: User
- **선행 조건**: A1
- **산출물**:
  - 백엔드 컨테이너 이미지 빌드 가능한 Dockerfile
- **완료 기준**:
  - 로컬에서 이미지 빌드 → 컨테이너 기동 → health 확인

---

## B. Claude 프론트 작업 (Owner: Claude)

> 기존 v1 UI/디자인 유지. 컴포넌트와 스타일 최대한 재사용. 지갑 트랜잭션 흐름 보존. 백엔드 연결을 위한 최소 변경 우선.

---

### B1. 프론트-백엔드 통합 계획 문서 작성

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음 (가장 먼저 수행)
- **산출물**:
  - `docs/frontend/backend-integration-plan.md`
  - 내용: 현재 `web/`에서 백엔드로 대체할 수 있는 데이터 소스 후보, 영향 받는 페이지/컴포넌트, 마이그레이션 우선순위, 환경변수, 에러/로딩 정책
- **완료 기준**:
  - 사용자가 문서를 보고 어떤 화면이 어떤 API로 연결되는지 한눈에 알 수 있다
  - 백엔드 미가용 시 fallback 정책 명시
- **참고**: 이 문서가 없으면 B2 이후 작업의 영향 범위가 불명확.

---

### B2. 백엔드 API 클라이언트 + 타입 정의

- [ ]
- **Owner**: Claude
- **선행 조건**: B1, A21(또는 A17~A21 중 첫 번째 가용 API)
- **산출물**:
  - `web/` 안의 API 클라이언트 모듈 (fetcher + 타입)
  - 베이스 URL 환경변수 도입
- **완료 기준**:
  - 5개 외부 API에 대한 타입과 호출 함수 존재
  - 응답이 api-spec.md와 정합

---

### B3. 트랜잭션 힌트 송신 통합

- [ ]
- **Owner**: Claude
- **선행 조건**: B2, A21
- **산출물**:
  - 사용자가 지갑으로 트랜잭션을 제출한 직후 `POST /api/tx-hints` 호출
- **완료 기준**:
  - OPEN/CLOSE 등 주요 액션에서 호출됨
  - 호출 실패해도 지갑 트랜잭션 자체에 영향 없음 (best-effort)
  - 중복 송신 정책이 A21 결정과 일치
- **참고**: 백엔드는 source of truth가 아님 (decisions.md §2). UI는 여전히 온체인 상태를 우선시한다.

---

### B4. 내 오픈 포지션 목록을 백엔드로 전환

- [ ]
- **Owner**: Claude
- **선행 조건**: B2, A18
- **산출물**:
  - 기존 화면의 데이터 소스를 `GET /api/users/{userAddress}/positions/open`으로 교체
- **완료 기준**:
  - UI 디자인 변경 없음
  - 빈 상태/로딩/에러 처리 추가
  - 백엔드 미가용 시 fallback 또는 명확한 에러 표기 (B1 결정 반영)

---

### B5. 포지션 타임라인 표시

- [ ]
- **Owner**: Claude
- **선행 조건**: B2, A20
- **산출물**:
  - 기존 포지션 상세 영역 또는 신규 섹션에 타임라인 표시
  - `OPENED / FEES_COLLECTED / CLOSED` 이벤트 카드 (기존 컴포넌트 재사용)
- **완료 기준**:
  - 페이지네이션 동작
  - 새 디자인 도입 없음
- **참고**: 기존 UI에 적합한 위치가 없다면 B1에서 합의된 위치에 한해 추가

---

### B6. 풀 가격 이벤트 차트/리스트

- [ ]
- **Owner**: Claude
- **선행 조건**: B2, A17
- **산출물**:
  - 기존 차트 컴포넌트가 있으면 데이터 소스 교체, 없으면 단순 리스트 표시
- **완료 기준**:
  - tick/sqrtPrice 표시
  - 페이지네이션 동작

---

### B7. Pending TX UX 표시

- [ ]
- **Owner**: Claude
- **선행 조건**: B3
- **산출물**:
  - 트랜잭션 제출 직후 PENDING 상태 표시
  - event-sync로 확정되면 CONFIRMED로 전환 (또는 일정 시간 후 폴링)
- **완료 기준**:
  - 지갑 트랜잭션 흐름이 깨지지 않음
  - 백엔드 응답 지연 시 UI가 멈추지 않음
- **참고**: 백엔드의 pending_tx 상태 머신과 정합 유지

---

### B8. 환경변수 / 빌드 설정

- [ ]
- **Owner**: Claude
- **선행 조건**: B2
- **산출물**:
  - 백엔드 베이스 URL 환경변수
  - 환경별 (`local`, `dev`, `prod`) 설정 파일 정리
- **완료 기준**:
  - README 또는 `docs/frontend/backend-integration-plan.md`에 사용법 명시
  - 사용자가 직접 값을 채워넣을 수 있는 형태

---

## C. Claude QA 작업 (Owner: Claude)

> 시나리오 문서/체크리스트 위주. 실제 테스트 코드 작성은 사용자 합의 시 별도 진행.

---

### C1. test-scenarios.md 보완

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - 기존 `docs/backend/test-scenarios.md`에 누락된 분기 보강
    - duplicate tx hint 정책 결정 후 시나리오 확정
    - unknown tokenId 응답 정책 확정
    - snapshot 부분 실패 정책 확정
- **완료 기준**:
  - 결정 사항과 시나리오가 일치
  - decisions.md와도 모순 없음

---

### C2. 프론트-백엔드 연동 통합 시나리오

- [ ]
- **Owner**: Claude
- **선행 조건**: B1
- **산출물**:
  - `docs/qa/integration-scenarios.md`
  - 내용: 트랜잭션 제출 → tx-hint → event-sync → read model → UI 갱신 흐름의 골든패스/실패 케이스
- **완료 기준**:
  - 각 단계의 관찰 포인트 (DB 행, API 응답, UI 상태)가 명시됨

---

### C3. Pending TX UX 시나리오

- [ ]
- **Owner**: Claude
- **선행 조건**: B7
- **산출물**:
  - `docs/qa/pending-tx-scenarios.md`
  - 내용: 백엔드 미가용, 백엔드 응답 지연, 트랜잭션 revert, reorg 등의 UI/UX 기대값
- **완료 기준**:
  - 각 케이스에서 사용자가 보는 화면 상태가 명시됨

---

### C4. event-sync 재실행/락/리커버리 정리

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/qa/event-sync-recovery.md`
  - 내용: 락 만료, 부분 실패 후 재시도, cursor 미전진 케이스, 동일 블록 재처리 시 idempotency 검증법
- **완료 기준**:
  - QA가 로컬에서 재현 절차를 따라할 수 있음
  - 운영(D) 문서와 교차 참조

---

### C5. snapshot 부분 실패 정책 매트릭스

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/qa/snapshot-failure-matrix.md`
  - 내용: lens 호출 실패 시 옵션(전체 실패/부분 진행)별 영향, 권장 옵션
- **완료 기준**:
  - 사용자가 결정 후 코드/decisions.md에 반영 가능한 비교표

---

### C6. API 응답 스키마 검증 체크리스트

- [ ]
- **Owner**: Claude
- **선행 조건**: A17~A21 중 일부
- **산출물**:
  - `docs/qa/api-schema-checklist.md`
  - 내용: 5개 외부 API와 2개 내부 API에 대한 필드 존재/타입/페이지네이션/에러 코드 체크리스트
- **완료 기준**:
  - api-spec.md와 1:1 매핑

---

### C7. 보안 시나리오 (내부 엔드포인트)

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/qa/security-scenarios.md`
  - 내용: `/internal/**` 미인증 호출, 잘못된 OIDC, 만료된 시크릿 헤더 등
- **완료 기준**:
  - test-scenarios.md §7 확장 + 운영 문서(D)와 정합

---

## D. Claude Ops 문서 작업 (Owner: Claude)

> 실제 인프라 적용은 사용자가 결정. Claude는 문서/절차 초안을 작성한다.

---

### D1. 운영 런북

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/ops/runbook.md`
  - 내용: 배포, 롤백, 수동 job 호출, lock 강제 해제, sync_cursor 수동 조정 절차
- **완료 기준**:
  - 운영자가 문서만 보고 따라할 수 있는 단계로 작성

---

### D2. Cloud Run 환경 설정 문서

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/ops/cloud-run-config.md`
  - 내용: 필수 env 목록 (DB, RPC, 시크릿, 인증), 동시성/메모리/타임아웃 권장값
- **완료 기준**:
  - A23(Dockerfile)과 정합

---

### D3. Cloud Scheduler 설정 문서

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/ops/cloud-scheduler-setup.md`
  - 내용: event-sync(1분) / snapshot(5분) 잡 정의, OIDC 설정, 재시도 정책 (scheduler-plan §10)
- **완료 기준**:
  - 사용자가 GCP 콘솔/IaC에 옮길 수 있는 수준

---

### D4. Observability 가이드

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/ops/observability.md`
  - 내용: `job_run` 기반 모니터링 쿼리, sync lag 산출법, 알람 후보 (실패율, lag, RPC 에러)
- **완료 기준**:
  - 알람 임계값은 권장값으로 제시 (확정은 사용자)

---

### D5. DB 운영 가이드

- [ ]
- **Owner**: Claude
- **선행 조건**: 없음
- **산출물**:
  - `docs/ops/db-operations.md`
  - 내용: 백업/복구, Flyway 마이그레이션 운영 절차, 인덱스 후보, jsonb 사용 시 주의점
- **완료 기준**:
  - 운영자가 마이그레이션 충돌 시 대응 절차를 알 수 있음

---

### D6. 인시던트 플레이북

- [ ]
- **Owner**: Claude
- **선행 조건**: D1, D4
- **산출물**:
  - `docs/ops/incident-playbook.md`
  - 내용: RPC 장애, DB 장애, lock stuck, sync 정체, snapshot 실패 폭증 등 케이스별 1차 대응
- **완료 기준**:
  - 각 케이스에 진단 → 임시 조치 → 항구 조치 흐름이 있음

---

## E. 의존성 / 권장 진행 순서

### E1. 백엔드(A) 권장 순서

1. A1 → A2 → A3 → A4 → A5
2. A6, A7 (병행 가능)
3. A8 → A9 → A10
4. A11 ⟂ A12 (병행 가능)
5. A13 (이전 항목 모두 필요)
6. A14 → A15 → A16
7. A17~A21 (read model이 준비된 항목부터 병행 가능)
8. A22 (배포 전 필수)
9. A23

### E2. 프론트(B) 권장 순서

1. B1 (선행)
2. B8, B2 (병행 가능)
3. B3 (A21 완료 후)
4. B4 (A18 완료 후)
5. B5 (A20 완료 후)
6. B6 (A17 완료 후)
7. B7 (B3 완료 후)

### E3. QA(C)

- C1, C4, C5, C7은 백엔드 구현과 무관하게 즉시 가능
- C2, C3은 B1 완료 후
- C6은 A17~A21 중 일부 가용 후

### E4. Ops(D)

- D1, D2, D4, D5는 즉시 가능
- D3은 A22 결정과 정합 필요
- D6은 D1, D4 후

---

## F. 미결정 사항 (의사결정 필요)

> 아래 항목은 사용자가 결정하면 본 문서와 관련 문서를 갱신해야 한다.

- F1. 중복 `txHash` 응답 정책: 멱등 성공 vs `409` (test-scenarios.md §1-2)
- ~~F2. unknown `tokenId` 응답~~ **결정 완료**: 빈 리스트 반환 (`[]`). 404 없음.
- F3. snapshot 부분 실패: 전체 실패 vs 개별 실패 후 계속 (test-scenarios.md §5-3)
- F4. `removed = true` 로그 처리 정책 (test-scenarios.md §8-2)
- ~~F5. `api-spec.md` 위치 정합화~~ **결정 완료**: 루트 `api-spec.md` 유지. CLAUDE.md 경로 수정 완료.
- F6. 정규화 정책:
  - 사용자 주소: **결정 완료** — 0x 포함 문자열 그대로 저장. 대소문자 정규화 없음.
  - 풀 ID: 미결정 — bytes32 hex 문자열 그대로 저장/조회할지 확인 필요.
- F7. RPC 제공자 선택 및 비용 한도
