# Ops Agent Log

## 2026-06-09 DB 비용 절감 — HikariCP 풀 축소 + Cloud SQL 다운그레이드

- 작업 목적
  - 월 ~5만원 GCP 비용의 주범인 Cloud SQL을 낮춰 비용 절감. 라이브 앱은 유지.
- 원인 분석
  - 비용 진단(gcloud 조회): Cloud Run 2개(forcast-web, forkcast-backend)는 scale-to-zero라 ~0원, Load Balancer·고정 IP 없음(Compute API 미활성). **비용 전부가 Cloud SQL `db-g1-small`(24h 상시)**.
  - SQL operations 이력: 2026-05-08 생성 직후 UPDATE 1건 → 처음 f1-micro로 만들었다가 g1-small로 올린 정황. 원인은 HikariCP 기본 풀 10개(idle 연결 = Postgres 프로세스 10개)가 f1-micro(0.6GB)를 압박한 것으로 추정.
- 읽은 파일
  - `backend/src/main/resources/application.yaml`
  - `docs/ops/cloud-run-config.md`, `docs/ops/db-operations.md`, `docs/ops/cloud-scheduler-setup.md`
- 변경한 파일
  - `backend/src/main/resources/application.yaml` — `spring.datasource.hikari` 추가 (`maximum-pool-size: 3`, `minimum-idle: 1`)
- 한 일
  - 백엔드 재배포: `gcloud run deploy forkcast-backend --source backend/ --region asia-northeast3` → 리비전 `forkcast-backend-00012-vw4` (env/secret/cloudsql 설정 보존)
  - DB 다운그레이드: `gcloud sql instances patch forkcast-defi-db --tier db-f1-micro` (재시작 ~11분, 데이터 보존)
  - 검증 (`GET /api/positions/open`):
    - Before(g1-small+풀10) 웜 ~88ms → After(f1-micro+풀3) 웜 ~103ms (+15ms, 무시 가능)
    - 동시 5요청(풀3 초과): 전부 200, ~170ms, 풀 고갈 에러 없음 (큐잉 정상)
    - 에러 로그: DB 재시작 윈도우(13:05~13:06)의 일회성 연결 끊김만, 이후 steady-state 깨끗. OOM 없음.
  - 비용: 월 ~5만원 → ~1.5만원 (연 ~42만원 절감)
- 왜 그렇게 했는지
  - "DB만 다운"하면 풀 10개가 다시 0.6GB를 압박해 예전 불안정 재발 위험. 뿌리 원인(풀 크기)을 먼저 줄여야 f1-micro가 안정적. 토이 인덱서 부하(5분 job 2개 + 가끔 조회)엔 풀 3이면 충분.
- 남은 문제
  - `GET /api/system/sync-status`가 500(INTERNAL_ERROR) — 기존 버그, 프론트 미사용으로 앱 작동 무관. 미해결로 둠.
  - f1-micro 체감 속도는 실제 프론트 UI 클릭으로 최종 확인 필요. 굼뜨면 풀 5로 상향 또는 티어 복구.

## 2026-05-22 백엔드 재배포 (Wave 1/2 수정 반영)

### 배포 내용

- 브랜치: `fix/sync-infrastructure`
- revision: `forkcast-backend-00011-bnc` (100% 트래픽)
- URL: `https://forkcast-backend-799298411936.asia-northeast3.run.app`

### 포함된 변경사항

| 커밋 | 내용 |
|------|------|
| `261c23e` | C-3: DB 패스워드 환경변수화 (`${DB_PASSWORD}`) |
| `334256a` | H-1: PendingTx TOCTOU 제거 (DB constraint → 409) |
| `1d6c31d` | H-2: StrategyPosition TOCTOU 제거 (ON CONFLICT DO NOTHING) |
| `951973a` | Wave 2: RPC/트랜잭션/타임스탬프/블록범위 개선 |

### 추가된 시크릿

- `DB_PASSWORD=forkcast-db-password:latest` (`--update-secrets`로 추가, 기존 secrets 유지)
- 배포 전 Cloud Run에 `DB_PASSWORD`가 없었고 `application.yaml:9`에 기본값 없이 `${DB_PASSWORD}` 사용 → 미추가 시 기동 실패였음

### 검증 결과

- 헬스체크 `/actuator/health` → `UP`
- CORS preflight `OPTIONS /api/positions/open` → `200`, `access-control-allow-origin: https://forcast-web-799298411936.asia-northeast3.run.app` 확인

### 절차

1. Cloud Scheduler (`forkcast-event-sync`, `forkcast-snapshot`) 일시 정지
2. `gcloud run deploy --source backend/ --update-secrets "DB_PASSWORD=forkcast-db-password:latest"`
3. 헬스/CORS 확인
4. Cloud Scheduler 재개

---

## 2026-05-15 프론트 재배포 (State History UI 개선)

### 배포 내용
- 브랜치: `fix/web-state-history-ui`
- 커밋: `d30dcd6` (fix(web): State History 모달 UI 개선)
- 이미지: `gcr.io/forkcast-defi-demo/forcast-web:latest` (Cloud Build `3ec0be95`)
- 서비스: `forcast-web` → revision `forcast-web-00010-k6b` (100% 트래픽)
- URL: `https://forcast-web-799298411936.asia-northeast3.run.app`
- HTTP 200 확인 완료

### 배포 중 발생한 문제 — TypeScript 빌드 에러 3개

첫 번째 `gcloud builds submit`이 실패했다. 이전 lint 수정 커밋(`7cb8adb`)과 UI 수정 커밋 사이에 생긴 TS 타입 에러 3개가 원인.

| 파일 | 에러 | 수정 |
|------|------|------|
| `src/hooks/useStrategyPositionView.ts:169` | `raw`가 `unknown`으로 추론돼 `.core` 접근 불가 | `(r.result ?? r) as RawContractView`로 캐스팅 |
| `src/hooks/useUserUniPositions.ts:119` | `.map()` 반환이 `unknown[]`인데 `Error[]`에 할당 | `.map((r) => r?.error as Error)` |
| `src/lib/demoTrader.ts:208` | `decoded.args`를 `{ tick: bigint }`로 직접 캐스팅 불가 | `as unknown as { ... }`로 double assertion |

`npx tsc --noEmit`으로 로컬 확인 후 재제출해서 성공.

### 환경변수 주의
- `NEXT_PUBLIC_BACKEND_URL`은 빌드 타임 arg로 주입 (`https://forkcast-backend-799298411936.asia-northeast3.run.app`)
- Secrets: `HOUSE_PK`, `RPC_URL`, `DEMO_TRADER_PRIVATE_KEY` — `--set-secrets`로 기존과 동일하게 유지

---

## 2026-05-15 data retention 배포

- revision `forkcast-backend-00009-jzb` → `forkcast-backend-00010-s8l`
- 변경 내용: job_run 14일·position_snapshot 7일 retention 로직 추가
- 00009는 `SnapshotWriteService.purgeOlderThan` 트랜잭션 전파 누락(`REQUIRED` → `REQUIRES_NEW` 수정 후 재배포)
- 배포 방식: `gcloud run deploy forkcast-backend --source backend/ --region asia-northeast3`
- 헬스 확인: `UP`

---

## 2026-05-08 release/v2 배포 및 장애 대응

### 배포 내용
- 브랜치: `fix-snapshot-batch-transaction` → `release/v2` 로 rename 후 GitHub push
- 백엔드: `gcloud run deploy forkcast-backend --source backend/` → revision `forkcast-backend-00005-vk4`
- 프론트: `gcloud builds submit --config cloudbuild.yaml` + `gcloud run deploy forcast-web` → revision `forcast-web-00009-9hb`

### 장애 1: CORS URL 불일치 (2번 반복됨)

**현상**: 배포 후 프론트에서 백엔드 API 호출 전혀 안 됨

**원인**: Cloud Run 서비스는 URL이 두 가지 형식으로 존재함
- `https://forcast-web-2hdyy43b3q-du.a.run.app` — hash 형식 (`gcloud run services list` 출력값)
- `https://forcast-web-799298411936.asia-northeast3.run.app` — project-number 형식 (`gcloud run deploy` 출력값)

유저가 실제 접속하는 URL은 **project-number 형식**이다. 백엔드 `APP_CORS_ALLOWED_ORIGINS`에 hash 형식만 등록돼 있어서 preflight 403으로 모든 API가 차단됨.

**이전에도 같은 실수를 했음 (재발)**. `web/infra/cloud-run/README.md`에 주의사항을 기록했으나 배포 시 확인하지 않았음.

**수정**: `APP_CORS_ALLOWED_ORIGINS`에 두 URL 모두 등록
```
https://forcast-web-2hdyy43b3q-du.a.run.app,https://forcast-web-799298411936.asia-northeast3.run.app
```

**배포 다음에 반드시 할 것**: CORS preflight 직접 확인
```bash
curl -sv -X OPTIONS \
  -H "Origin: https://forcast-web-799298411936.asia-northeast3.run.app" \
  -H "Access-Control-Request-Method: GET" \
  https://forkcast-backend-799298411936.asia-northeast3.run.app/api/positions/open \
  2>&1 | grep "access-control-allow\|< HTTP"
```

### 장애 2: `--set-env-vars`로 백엔드 env 전체 삭제

**원인**: CORS 수정 시 `--update-env-vars` 대신 `--set-env-vars` 사용 → 기존 env var 전체 삭제됨. `SPRING_DATASOURCE_URL`, `STRATEGY_ROUTER_ADDRESS` 등 필수 값이 모두 날아가 컨테이너 기동 실패.

**Cloud Run env var 수정 규칙**:
- ✅ `--update-env-vars` — 지정한 키만 추가/변경, 나머지 유지
- ❌ `--set-env-vars` — 지정한 키만 남기고 나머지 **전부 삭제**. 절대 사용 금지

쉼표가 포함된 값(CORS URL 목록 등) 수정 시 구분자 이스케이프 필요:
```bash
--update-env-vars "^|^KEY=val1,val2"   # | 를 구분자로 사용
```

**복구 방법**: 이전 정상 revision(`forkcast-backend-00005-vk4`)의 env를 `gcloud run revisions describe`로 확인 후 `--update-env-vars`로 전체 복원. Cloud SQL 연결은 `--add-cloudsql-instances`도 별도로 복원 필요.

### 장애 3: demo trader allowance 소진

**원인**: 코드 구버전에 `approve(100)` 로직이 있었고, 해당 버전으로 데모 트레이드가 실행되면서 기존 무한대 allowance가 100으로 덮어써진 후 스왑으로 전액 소진됨. 현재 코드는 approve 로직 없이 사전 approve를 전제로 동작.

**수정**: 터미널에서 직접 `uint256.max` approve 트랜잭션 전송
- AAVE approve tx: `0xb069cf0977a500352aef2594b3b5999aba483ff9453558a951bd2d50b30dceab`
- LINK approve tx: `0xa6c27090bed48829d0c3eeb5c2d444edd4b6567045524154b464b56d2e3a58ca`

**재발 방지**: demo trader는 매 실행마다 approve하지 않는 구조이므로, allowance가 소진되면 수동으로 다시 approve해야 함. 소진 여부 확인 방법:
```js
// AAVE/LINK allowance 조회 (demo trader → MiniSwapRouter)
// trader: 0xde589C867174C349d00e9b582867aF5c13A74679
// router: 0xfeef88095Aa49d4D296d0746d28E2D050b3C1153
```

---

## 2026-05-08 DEMO_TRADER_PRIVATE_KEY Secret Manager 누락 확인

- 작업 목적
  - 프론트 배포에서 `DEMO_TRADER_PRIVATE_KEY`가 Cloud Run에 주입되지 않은 문제 확인
- 읽은 파일
  - `web/infra/cloud-run/README.md`
  - `web/src/lib/demoTrader.ts`
  - `web/.env.example`
- 변경한 파일
  - `web/infra/cloud-run/README.md` — `--set-secrets`에 `DEMO_TRADER_PRIVATE_KEY` 추가, 환경변수 테이블에도 항목 추가
- 한 일
  - `gcloud run services describe forcast-web`으로 현재 Cloud Run env 확인 → `DEMO_TRADER_PRIVATE_KEY` 없음
  - `gcloud secrets list`로 Secret Manager 확인 → 시크릿 자체가 미생성 상태
  - `demoTrader.ts:102-104`에서 키 없으면 즉시 throw 확인
- 왜 그렇게 했는지
  - `.env.example`에는 명시됐지만 배포 문서와 실제 deploy 커맨드에서 누락됨
  - Secret Manager에 시크릿 자체가 없으므로 배포 전 생성이 선행돼야 함
- 조치 결과
  1. Secret Manager에 시크릿 생성 완료
  2. Cloud Run SA(`799298411936-compute@developer.gserviceaccount.com`)에 `secretAccessor` 권한 부여
  3. `gcloud run services update --update-secrets`로 재빌드 없이 런타임 env 주입 완료
  4. `forcast-web-00008-xr7` revision 배포 완료, 동작 확인됨

## 2026-05-08 NEXT_PUBLIC_POOL_ID 빌드 주입 추가 및 재배포

- 작업 목적
  - 프론트에서 "NEXT_PUBLIC_POOL_ID is not configured" 메시지 제거
- 읽은 파일
  - `web/cloudbuild.yaml`, `web/Dockerfile`
- 변경한 파일
  - `web/cloudbuild.yaml` — `_NEXT_PUBLIC_POOL_ID` substitution 추가
  - `web/Dockerfile` — `ARG/ENV NEXT_PUBLIC_POOL_ID` 추가
  - `docs/ops/cloud-run-config.md`, `web/infra/cloud-run/README.md` — 배포 명령에 `_NEXT_PUBLIC_POOL_ID` 반영
- 한 일
  - Pool ID `0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c` build arg로 주입
  - `gcloud builds submit --substitutions ...,_NEXT_PUBLIC_POOL_ID=$POOL_ID` 로 재빌드
  - `forcast-web-00006-78h` 배포 완료 (기존 `forcast-web` 서비스에 새 revision)
  - 번들 `8a47ce62cbb81146.js`에서 pool ID 삽입 확인
  - `GET /api/pools/{poolId}/price-events` → tick=1401 응답 확인
- 남은 문제
  - 앞으로 `NEXT_PUBLIC_*` 추가될 때마다 `cloudbuild.yaml`, `Dockerfile`, 배포 문서 세 곳 모두 업데이트 필요

## 2026-05-08 프론트 재빌드 & API 연동 검증 완료

- 작업 목적
  - 수정된 build-time 주입 절차로 프론트 재빌드 후 실제 API 연동 확인
- 한 일
  - `gcloud builds submit --config cloudbuild.yaml --substitutions _NEXT_PUBLIC_BACKEND_URL=...` 로 재빌드
  - 빌드 성공, `gcr.io/forkcast-defi-demo/forcast-web:latest` 푸시 완료
  - `gcloud run deploy forcast-web` 배포 완료, 새 revision: `forcast-web-00005-cq6`
  - JS 번들 `0313684a0800fbac.js`에서 `forkcast-backend-2hdyy43b3q-du.a.run.app` 확인, `localhost:8080` 없음
  - **CORS 불일치 발견 & 수정**: `APP_CORS_ALLOWED_ORIGINS`이 `https://forkcast-web-...` (k 있음)로 잘못 설정 → `https://forcast-web-2hdyy43b3q-du.a.run.app` (서비스명 그대로)로 수정
  - 백엔드 새 revision: `forkcast-backend-00004-p6h`
- 검증 결과
  - `access-control-allow-origin: https://forcast-web-2hdyy43b3q-du.a.run.app` 응답 확인
  - `GET /api/positions/open` → tokenId=32457 응답 성공
  - `GET /api/positions/32457/timeline` → OPENED 이벤트 확인
  - `GET /api/positions/32457/snapshots` → 3건 확인
  - `POST /api/tx-hints` preflight → 200
- 현재 상태
  - 프론트: `https://forcast-web-2hdyy43b3q-du.a.run.app` (revision forcast-web-00005-cq6)
  - 백엔드: `https://forkcast-backend-2hdyy43b3q-du.a.run.app` (revision forkcast-backend-00004-p6h)
  - 번들 내 백엔드 URL: `https://forkcast-backend-2hdyy43b3q-du.a.run.app`
- 남은 문제
  - `NEXT_PUBLIC_POOL_ID` 빌드 시 미설정 → HookEventSection 비활성화 상태
  - 프론트 RPC 관련 env (`NEXT_PUBLIC_RPC_URL` 등) 미설정이면 컨트랙트 조회는 퍼블릭 RPC 사용 중

## 2026-05-08 프론트-백엔드 연결 실패 원인 수정

- 작업 목적
  - 배포 후 프론트에서 백엔드 연결이 전혀 안 되는 문제 원인 파악 및 문서/절차 수정
- 읽은 파일
  - `web/Dockerfile`
  - `web/cloudbuild.yaml`
  - `docs/ops/cloud-run-config.md`
  - `web/infra/cloud-run/README.md`
  - `docs/ops/db-operations.md`
  - `backend/build.gradle`
  - `backend/src/main/resources/db/migration/V1__init_schema.sql`
- 변경한 파일
  - `docs/ops/cloud-run-config.md` §2-2, §2-3
  - `web/infra/cloud-run/README.md`
  - `docs/ops/db-operations.md` §6-2
- 한 일
  - **Issue 1 (연결 실패 직접 원인)**: `NEXT_PUBLIC_BACKEND_URL` 주입 방식 문서 수정
    - 기존 문서: `gcloud run deploy --update-env-vars NEXT_PUBLIC_BACKEND_URL=...` (런타임 env → 효과 없음)
    - 수정 후: `gcloud builds submit --config cloudbuild.yaml --substitutions _NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL` (빌드 타임 build arg)
    - `web/Dockerfile`은 이미 `ARG NEXT_PUBLIC_BACKEND_URL → ENV → npm run build` 구조로 올바름, 문서만 틀렸던 것
    - `gcloud run deploy`에서 `--update-env-vars NEXT_PUBLIC_BACKEND_URL=...` 제거
    - 두 파일 모두 build-time 주입임을 명시하는 주의사항 추가
  - **Issue 2 (오탐)**: `postgres-socket-factory:1.23.1`이 `build.gradle`에 이미 존재 → 의존성 문제 없음, 문서 의존성 출처 표현만 정확하게 수정
  - **Issue 3**: `db-operations.md` §6-2의 `raw_chain_event.created_at` 쿼리를 `event_timestamp`로 교체 (`raw_chain_event`에 `created_at` 컬럼 없음)
- 왜 그렇게 했는지
  - Next.js `NEXT_PUBLIC_*`은 webpack DefinePlugin으로 번들에 정적 삽입, 런타임 env로 교체 불가
  - `gcloud builds submit --tag` 방식은 build arg 전달을 지원하지 않아 `cloudbuild.yaml` 방식이 유일한 정상 경로
- 남은 문제
  - 현재 배포된 프론트 번들은 `NEXT_PUBLIC_BACKEND_URL=http://localhost:8080`으로 빌드된 상태일 가능성 높음
  - **수정된 절차로 프론트를 재빌드 + 재배포해야 실제 연결이 된다**
  - 재빌드 후에도 연결 안 되면 백엔드 CORS 설정(`APP_CORS_ALLOWED_ORIGINS`) 재확인 필요

## 2026-05-08 GCP 실제 배포 완료

### 생성된 리소스

| 리소스 | 값 |
|--------|----|
| 프로젝트 | `forkcast-defi-demo` |
| 리전 | `asia-northeast3` |
| Cloud SQL | `forkcast-defi-db` (POSTGRES_16, db-g1-small) |
| DB / 유저 | `forkcast_defi` / `forkcast_app` |
| 백엔드 Cloud Run | `forkcast-backend` |
| 프론트 Cloud Run | `forcast-web` (기존 서비스 재배포) |
| Scheduler job | `forkcast-event-sync`, `forkcast-snapshot` (5분 간격) |

### URL

- 백엔드: `https://forkcast-backend-799298411936.asia-northeast3.run.app`
- 프론트: `https://forcast-web-2hdyy43b3q-du.a.run.app`

### Secret Manager

| Secret | 내용 |
|--------|------|
| `forkcast-db-password` | forkcast_app 유저 비밀번호 (임의 생성) |
| `forkcast-rpc-url` | Sepolia Infura RPC URL |
| `HOUSE_PK` | 기존 프론트 서비스 키 (복구) |
| `RPC_URL` | 기존 프론트 서비스 RPC URL (복구) |

### 코드 변경 사항

- `backend/build.gradle` — `postgres-socket-factory:1.23.1` 추가 (Cloud SQL 소켓 연결)
- `backend/Dockerfile` — 신규 생성
- `web/Dockerfile` + `web/cloudbuild.yaml` — 신규 생성, `NEXT_PUBLIC_BACKEND_URL` build arg 주입
- `web/next.config.ts` — `output: "standalone"` 추가

### 검증 결과

- 백엔드 헬스: `UP`
- 내부 endpoint: 토큰 없이 `401` 확인
- Scheduler → 백엔드 OIDC 인증: `200` 확인
- 프론트 번들에 `NEXT_PUBLIC_BACKEND_URL` 주입 확인

## 2026-05-08 GCP 배포 ops 문서 전체 작성

- 작업 목적
  - backend + db + scheduler 운영 구성을 문서와 gcloud 명령 수준으로 완성
  - 프론트는 기존 `forcast-web` 서비스 재배포 방식임을 명시
- 읽은 파일
  - `docs/backend/decisions.md`
  - `docs/backend/scheduler-plan.md`
  - `api-spec.md`
  - `docs/agent-logs/ops.md`
  - `web/infra/cloud-run/README.md`
  - `backend/build.gradle`
- 변경/생성한 파일
  - `docs/ops/README.md` — ops 문서 인덱스 신규 작성
  - `docs/ops/cloud-run-config.md` — 백엔드/프론트 Cloud Run 구성 전체
  - `docs/ops/cloud-scheduler-setup.md` — Cloud Scheduler job 생성 및 인증 흐름
  - `docs/ops/db-operations.md` — Cloud SQL, Secret Manager, Flyway, 일상 운영
  - `web/infra/cloud-run/README.md` — 프론트 덮어쓰기 배포 절차로 전면 보강
- 한 일
  - Cloud SQL 인스턴스명(`forkcast-defi-db`), DB명(`forkcast_defi`), 앱 유저(`forkcast_app`) 확정
  - Secret Manager에 보관할 값 2개 정리: `forkcast-db-password`, `forkcast-rpc-url`
  - Cloud Run env 변수 13개 전체 정리 (민감/비민감 구분)
  - 백엔드 선배포 → URL 확정 → audience/cors env 재설정 순서 명시
  - `NEXT_PUBLIC_BACKEND_URL`을 확정 백엔드 URL로 설정 후 프론트 재배포 절차 명시
  - `forcast-web` 기존 서비스 revision 덮어쓰기 방식 명시 (새 서비스 생성 아님)
  - 트래픽 전환/롤백 gcloud 명령 작성
  - Flyway 마이그레이션 절차 및 실패 복구 방법 작성
  - Cloud Scheduler OIDC 인증 흐름 요약 포함
  - 배포 후 smoke test 명령 작성
- 왜 그렇게 했는지
  - Cloud Run scale-to-zero 환경에서 Spring @Scheduled 대신 Cloud Scheduler가 필요한 구조를 decisions.md 기반으로 반영
  - 백엔드 URL이 선배포 전까지 미확정이므로 PLACEHOLDER → 재설정 순서를 명시해야 ENV 누락을 방지
  - 프론트가 기존 서비스를 쓰므로 새 서비스 생성 시 URL 변경 문제를 피해야 함
- 남은 문제
  - `PROJECT_ID`, `REGION`, 실제 contract 주소는 사용자가 직접 확인 후 채워야 함
  - `db-f1-micro` 티어는 운영 트래픽 증가 시 상향 필요
  - job_lock lease 2분 제한은 block range/포지션 수 증가 시 재검토 필요

## 2026-05-04 event-sync 최초 bootstrap env 메모

- 작업 목적
  - 클라우드 첫 배포 시 `event-sync`가 제네시스부터 스캔하지 않도록 bootstrap env var 위치와 기본값을 남긴다
- 읽은 파일
  - `docs/backend/scheduler-plan.md`
  - `docs/agent-logs/ops.md`
- 변경한 파일
  - `docs/backend/scheduler-plan.md`
  - `docs/agent-logs/ops.md`
- 한 일
  - `SYNC_BOOTSTRAP_WINDOW_BLOCKS` env var를 운영 문서에 추가
  - 기본값 `25`와 의미를 적었다
  - Cloud Run / IntelliJ / 로컬 shell 어디에 넣는지 명시했다
- 왜 그렇게 했는지
  - 다른 작업자가 새 배포 환경을 만들 때 env var 이름을 놓치면 첫 `event-sync` 범위가 의도와 다르게 보일 수 있어서
- 남은 문제
  - 실제 운영에서 `25`블록이 너무 짧거나 길면 배포 후 조정할 수 있다

## 2026-05-01 프론트 확인용 더미 데이터 시드

- 작업 목적
  - 빈 박스로 보이던 프론트 화면을 확인할 수 있게 현재 지갑 주소 기준 더미 데이터를 DB에 넣고 내부 job도 다시 실행
- 읽은 파일
  - `docs/backend/data-model.md`
  - `backend/src/main/resources/db/migration/V1__init_schema.sql`
- 변경한 파일
  - `docs/agent-logs/ops.md`
- 한 일
  - 현재 지갑으로 보이는 `0x9cf7b6b56c9bc0ab6c0c0d60db8c8b5fa67c5f6e` 기준으로 더미 데이터 시드
  - 채운 테이블:
    - `user_vault`
    - `pending_tx`
    - `raw_chain_event`
    - `strategy_position`
    - `position_timeline`
    - `pool_price_event`
    - `position_snapshot`
  - 대표 더미 포지션:
    - `token_id = 990001`
    - `is_open = true`
    - `vault_address = 0xb88fff9ab45b0caaeebe8d40bd5d8545eb6486b6`
  - 확인 결과:
    - `GET /api/users/0x9cf7b6b56c9bc0ab6c0c0d60db8c8b5fa67c5f6e/positions/open?limit=20` 에서 `tokenId=990001` 확인
    - `GET /api/positions/990001/timeline?limit=20` 에서 `OPENED`, `FEES_COLLECTED` 확인
    - `GET /api/pools/{poolId}/price-events?limit=5` 에서 더미 `tick=219`, `tick=205` 최신값 확인
  - 내부 job 재실행:
    - `POST /internal/jobs/event-sync`
    - 결과: `SUCCESS`, `processedEvents=0`, `updatedCursor=10766882`
- 왜 그렇게 했는지
  - 프론트가 실제 API 연동 UI를 바로 볼 수 있으려면 현재 사용자 기준 오픈 포지션, 타임라인, 가격 이벤트, 스냅샷 예시가 필요해서
- 남은 문제
  - 이번 더미 데이터는 체인 기반이 아니라 로컬 DB 시드 데이터다
  - 실제 세폴리아 신규 포지션은 아직 sync 결과에 잡히지 않았다

## 2026-05-01 0x7a227D... 주소용 타임라인 더미 보강

- 작업 목적
  - `1-4 /api/positions/{tokenId}/timeline` 프론트 확인이 되도록 기존 실제 오픈 포지션 `tokenId=20891`에 더미 활동 로그를 추가
- 읽은 파일
  - `docs/backend/data-model.md`
  - `backend/src/main/resources/db/migration/V1__init_schema.sql`
- 변경한 파일
  - `docs/agent-logs/ops.md`
- 한 일
  - 주소 `0x7a227d5902ca52c0c3c61304533bff4632fce145`의 기존 오픈 포지션 `tokenId=20891` 확인
  - 기존에는 `OPENED` 1건만 있던 `position_timeline`에 `FEES_COLLECTED` 2건 추가
  - 관련 보조 데이터도 함께 추가:
    - `user_vault`
    - `pending_tx`
    - `raw_chain_event`
    - `pool_price_event`
    - `position_snapshot`
  - 확인 결과:
    - `GET /api/users/0x7a227d5902ca52c0c3c61304533bff4632fce145/positions/open?limit=20` 에서 `tokenId=20891` 유지
    - `GET /api/positions/20891/timeline?limit=20` 에서 `FEES_COLLECTED`, `FEES_COLLECTED`, `OPENED` 3건 확인
- 왜 그렇게 했는지
  - 전체 오픈 포지션을 새로 만들기보다 현재 실제 열려 있는 포지션에 활동 로그를 보강하는 편이 프론트 검증에 더 안전해서
- 남은 문제
  - 이번 더미 타임라인과 snapshot은 체인에서 수집된 실제 데이터가 아니라 로컬 검증용이다
