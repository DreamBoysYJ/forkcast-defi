# Backend Future Risks & Improvement Points

> Date: 2026-05-19
> 목적: v1 백엔드의 잠재 취약점, 운영 중 발생할 수 있는 문제, 발전 포인트를 한 곳에 정리.
> 보완 대상: `release-risk-review.md` (2026-05-08, R1~R4 + D1~D3) 이후 추가로 발견된 항목 포함.
>
> AI agent가 이 문서만 읽고 어디를 손봐야 할지 판단할 수 있도록 항목마다 위치와 영향을 명시.

---

## 1. 보안 (Security)

### S1. DB 비밀번호 평문 하드코딩 — **즉시 수정 권장**

- 위치: `backend/src/main/resources/application.yaml:9`
- 현재: `password: 1234`
- 영향: 레포 노출 시 자격증명 유출. 운영 DB도 같은 패턴이면 critical.
- 조치: `${DB_PASSWORD}` 환경변수화. 운영은 Secret Manager 경유.

### S2. `IllegalArgumentException`을 통한 internal 메시지 노출

- 위치: `common/api/GlobalExceptionHandler.java:22-30`
- 현재: 모든 `IllegalArgumentException`을 `400 BAD_REQUEST`로 매핑하고 `e.getMessage()`를 그대로 응답.
- 영향: `"strategy_position not found: tokenId = 12345"`, `"Sync Cursor not found: ..."` 같은 내부 상태가 외부 API 응답에 노출됨. injection 정보 노출은 아니지만 정보 누설.
- 조치: 외부 입력 검증 실패와 내부 invariant 위반을 분리. 후자는 500 또는 generic 메시지로.

### S3. `DUPLICATE_TX_HASH` 분기 영구 미실행 — **실제 버그**

- 위치: `common/api/GlobalExceptionHandler.java:24` ↔ `txHint/service/PendingTxService.java:21`
- 현재:
  - PendingTxService throw: `"Pending tx already exists : " + txHash` (공백 + 콜론 + 공백)
  - Handler match: `startsWith("Pending tx already exists:")` (공백 없는 콜론)
- 영향: 중복 txHash가 항상 `400 BAD_REQUEST`로 떨어지고, 의도한 `409 CONFLICT` + `DUPLICATE_TX_HASH` 코드가 절대 발생하지 않음.
- 조치: 문자열 매칭 의존 제거. 전용 예외 클래스(`DuplicatePendingTxException`) 도입 권장.

### S4. validation 에러 메시지 문법 깨짐

- 위치: `common/api/GlobalExceptionHandler.java:17`
- 현재: `fieldError.getField() + "must not be blank"` → `"txHashmust not be blank"`로 출력.
- 영향: 사용자/프론트 디버깅 혼란. 보안은 아님.
- 조치: `" must not be blank"` 또는 `fieldError.getDefaultMessage()` 사용.

### S5. CORS `allowed-origins` 파싱 trim 누락

- 위치: `common/config/WebMvcConfig.java:31` (`split(",")`)
- 영향: env에 `"a.com, b.com"`처럼 공백 포함 시 두 번째 origin 매칭 실패.
- 조치: `.map(String::trim)` 추가.

### S6. Scheduler audience 미설정 시 검증 우회 가능성

- 위치: `job/auth/SchedulerTokenVerifier.java:27` + `application.yaml:31`
- 현재: `SCHEDULER_AUTH_AUDIENCE` env 기본값 빈 문자열. `setAudience(Collections.singletonList(""))`로 검증기 생성.
- 영향: GoogleIdTokenVerifier 동작상 빈 audience는 매치 실패하여 거부될 가능성이 높지만, 운영자가 실수로 `SCHEDULER_AUTH_ENABLED=true` + audience 빈 상태로 띄우면 모든 요청 거부 (가용성 이슈) 또는 라이브러리 버전에 따라 우회 위험.
- 조치: `@PostConstruct`로 enabled=true인데 audience/service account가 비어있으면 fail-fast.

### S7. 외부 API input 검증 부재

- 위치: `position/controller/OpenPositionController.java`, `pool/controller/PoolPriceEventController.java` 등 모든 read controller
- 현재: `userAddress`, `poolId`, `tokenId` 형식 검증 없음. `limit` 상한 없음.
- 영향: `limit=1000000`로 DB 부담. 잘못된 주소 포맷이 DB에 그대로 쿼리 (JPA로 SQLi 위험은 낮음, 비용/오용 위험).
- 조치: `@Pattern`/`@Max(100)` 등 Bean Validation 적용.

---

## 2. 동시성 / Lock / Job lifecycle

### C1. event-sync 메인 트랜잭션이 여전히 RPC 포함 — **release-risk R4 패턴 미적용**

- 위치: `sync/service/EventSyncService.java:30` (클래스 `@Transactional`) + `run()` 전체
- 현재: snapshot은 R4로 해결됐지만 event-sync는 `@Transactional` 클래스에서 RPC 호출(`getLatestBlockNumber`, `getLogs` 두 번) → DB write를 한 트랜잭션 내에서 수행. RPC가 느리면 DB connection을 길게 점유, lock lease 만료 위험.
- 조치: snapshot처럼 RPC를 트랜잭션 바깥에서 수집 후 write 서비스 분리.

### C2. lock lease 2분 고정, 연장 메커니즘 없음

- 위치: `sync/service/EventSyncService.java:79`, `snapshot/service/SnapshotService.java:56`
- 현재: 2분 lease + 연장 없음. snapshot이 포지션 수 증가나 RPC 지연으로 2분 초과 시 두 번째 인스턴스가 lock 재획득.
- 영향: 동일 snapshot/이벤트 중복 처리. unique 제약이 막아주지만 트랜잭션 충돌·실패 발생.
- 조치: heartbeat 연장 또는 lease를 work load 기반으로 산정. scheduler-plan §5에 이미 documented risk.

### C3. `job_run`이 STARTED 상태로 영구 stuck

- 위치: `sync/service/EventSyncService.java:209-212`, `snapshot/service/SnapshotService.java:149-152`
- 현재: `markFailed` 실패를 catch로 swallow. 메인 실패 시 `job_run.status = STARTED` 그대로 남음.
- 영향: 모니터링이 "실행 중"으로 잘못 인식. 실패 통계 왜곡.
- 조치: 최소한 ERROR 로깅 + 별도 alert. fallback `markFailed` 재시도 또는 별도 sweeper job.

### C4. `existsBy` + `save` 패턴의 race window — R-D2 후속

- 위치: `txHint/PendingTxService.java:20`, `chain/RawChainEventService.java:34`, `pool/PoolPriceEventService.java:28`
- 현재: check-then-insert. 동시 요청 시 둘 다 통과 → 두 번째가 unique 위반.
- 영향: 두 번째 호출이 `DataIntegrityViolationException` → 500. 멱등성 보장 안 됨.
- 조치: PostgreSQL `INSERT ... ON CONFLICT DO NOTHING` 패턴으로 전환.

### C5. `SchedulerAuthInterceptor` 토큰 검증 매 요청 외부 호출

- 위치: `job/auth/SchedulerTokenVerifier.java:22-29`
- 현재: 요청마다 `new GoogleIdTokenVerifier.Builder(new NetHttpTransport(), ...)` 생성 → 매 검증 시 Google 공개키 조회.
- 영향: scheduler가 5분 간격이라 큰 비용은 아니지만 cold start 지연, RPC 실패 시 모든 job 정지.
- 조치: verifier를 `@Bean`으로 싱글톤화하고 PublicKeysManager 캐시 활용.

---

## 3. 데이터 정합성 / Reorg

### D1. reorg `removed=true` 로그를 read model에 그대로 projection — 미결정 정책 F4

- 위치: `chain/service/RawChainEventService.java:47` (raw에 저장) + `sync/service/EventSyncService.java:154-181` (projection은 removed 무시)
- 현재: `log.isRemoved()` 값을 raw에만 저장. projection은 어떤 raw가 invalidated 됐는지 모름.
- 영향: 5블록보다 깊은 reorg 발생 시 잘못된 포지션이 영구적으로 read model에 잔존.
- 조치: 우선 projection 단계에서 `removed=true` skip. 장기적으로 block_hash 기반 reorg 감지 + rewind.

### D2. safe-head 오프셋 5블록 부족 가능

- 위치: `sync/service/EventSyncService.java:37` (`SAFE_HEAD_OFFSET = 5`)
- 현재: Sepolia 기준 보통 충분하지만 finality는 ~64블록(2 epoch). 5블록 deep reorg 발생 가능.
- 영향: read model 데이터 손실/오염.
- 조치: env로 분리. mainnet 전환 시 12~32블록 이상 권장.

### D3. event_timestamp = ingest time (`Instant.now()`)

- 위치: `chain/service/RawChainEventService.java:46`, `position/service/PositionTimelineService.java:43/68/96`, `pool/service/PoolPriceEventService.java:41`
- 현재: 모든 timestamp가 ingest 시점.
- 영향: 시계열 정렬·차트가 실제 chain 시간과 어긋남. 가장 두드러지는 곳: pool_price_event 차트.
- 조치: `eth_getBlockByNumber`로 block timestamp 한 번 조회 또는 batch.

### D4. pre-bootstrap 포지션의 `PositionClosed`/`FeesCollected` → 전체 sync 영구 stuck — release-risk R2 미해결

- 위치: `position/service/StrategyPositionService.java:54`, `position/service/PositionTimelineService.java:87`
- 현재: tokenId 못 찾으면 throw → event-sync 실패 → cursor 미전진 → 다음 실행도 같은 로그에서 같은 throw.
- 영향: 한 번 발생하면 전체 백엔드 정지. release-risk-review에서 release blocker로 식별됨.
- 조치: skip-with-audit 또는 lazy reconstruction 정책 결정 후 구현.

### D5. snapshot `is_open` 시점 불일치

- 위치: `snapshot/service/SnapshotService.java:82-119`
- 현재: `findByIsOpenTrue()` 시점과 RPC 호출 시점 사이에 포지션이 close되면 snapshot은 `is_open=true`로 저장됨 (StrategyPosition 객체 캐시 기반).
- 영향: snapshot에서 "open처럼 보이는 closed position" 등장 가능. 빈도 낮음.
- 조치: snapshot insert 직전 fresh check 또는 closed 상태도 함께 기록.

### D6. cursor `getOrCreate` race

- 위치: `sync/service/SyncCursorService.java:25-28`
- 현재: `findById` → `save` 패턴. 두 인스턴스 첫 부팅 시 동시에 들어가면 둘 다 save 시도.
- 영향: PK 충돌 예외. job_lock으로 대부분 막히지만 lock 획득 직후 cursor 생성 race 잔존.
- 조치: `ON CONFLICT DO NOTHING` + 재조회.

---

## 4. 운영 / 리소스 / 안정성

### O1. RPC 호출 timeout/재시도 없음

- 위치: `sync/client/Web3jChainClient.java:22-58`, `snapshot/client/StrategyLensClient.java:107-122`
- 현재: web3j 기본 동작. 네트워크 지연 시 무한 wait 가능. IOException 시 즉시 propagate.
- 영향: lock lease(2분) 만료, 전체 job 실패. RPC provider 일시 장애 시 매 실행 실패.
- 조치: web3j HTTP client에 connect/read timeout 설정. 일시 오류는 짧은 retry (지수 백오프 3회).

### O2. snapshot RPC 순차 실행

- 위치: `snapshot/service/SnapshotService.java:82-119`
- 현재: open position 수 × 2 RPC를 순차 호출.
- 영향: 포지션 30개면 2분 lease 초과 가능.
- 조치: batch (`eth_call` multicall) 또는 병렬 (RPC provider rate limit 고려).

### O3. eth_getLogs 블록 범위 상한 없음

- 위치: `sync/service/EventSyncService.java:124-143`
- 현재: cursor와 latestBlock 차이만큼 한 번에 요청. 사고/지연 후 따라잡을 때 큰 range가 RPC provider에서 거부됨 (Infura/Alchemy 보통 10k blocks 상한).
- 조치: per-call 상한(예: 2000)으로 chunking.

### O4. retention purge 하드코딩 — 백엔드-리뷰 로그에 이미 명시

- 위치: `sync/service/EventSyncService.java:190` (`14`), `snapshot/service/SnapshotService.java:124` (`7`)
- 영향: 운영 중 보존 기간 조정 시 코드 변경/배포 필요.
- 조치: `@ConfigurationProperties`로 분리.

### O5. 운영 도구 부재

- 현재: lock 강제 해제, cursor 수동 조정, raw event replay 모두 SQL 직접 실행 필요.
- 영향: 사고 대응 시간 증가, 휴먼 에러 위험.
- 조치: 보호된 admin endpoint 또는 CLI 명령.

### O6. 메트릭/구조화 로깅 없음

- 현재: `log.info/warn`만 사용. Cloud Monitoring 메트릭 export 없음.
- 영향: sync lag, 실패율 알람을 `job_run` 쿼리에 의존.
- 조치: Micrometer + Cloud Monitoring, sync lag(`latestBlock - cursor`) gauge.

### O7. PoolPriceEventController 등 API 응답에 NULL `nextCursor` 고정

- 위치: 모든 list controller (`OpenPositionController.java:33` 등)
- 현재: pagination 미구현, `limit`만 지원. 클라이언트는 데이터 끊김을 알 수 없음.
- 영향: 데이터 증가 시 UI에서 일부만 보이고 끝.
- 조치: cursor 기반 페이지네이션 (token_id, id, snapshot_at 등 단조 컬럼).

---

## 5. 테스트 / 회복력

### T1. 테스트 커버리지 얇음 — release-risk-review D3

- 영향: lock, cursor, retry, projection 멱등성 회귀 위험.
- 우선 추가할 테스트:
  - 동일 raw event 재처리 시 read model 불변
  - lock 동시 획득 시 단 한 쪽만 성공
  - `PositionClosed`가 pre-bootstrap 시 동작 (D4 정책 결정 후)
  - snapshot 부분 실패 시 성공한 행은 저장

### T2. integration test fixture 부재

- 영향: 실제 PostgreSQL 동작(트리거, unique 위반, ON CONFLICT 등) 검증 불가.
- 조치: Testcontainers 도입.

---

## 6. 발전 방향 (Future Work)

운영 안정화 후 검토:

1. **Reorg 안전**: block_hash 검증 + rewind/rebuild 흐름. read model을 raw로부터 재생성 가능하게 유지.
2. **PnL 계산**: snapshot 시계열 + price event 결합.
3. **알림/추천**: health_factor 임계 도달 시 알림, 재포지션 제안.
4. **multi-pool / multi-chain**: pool_id가 이미 schema에 있으므로 sync 설정만 다중화하면 확장 가능.
5. **backfill 도구**: 임의 블록 범위 재처리 명령. cursor 분리(`event-sync-latest`, `backfill-*`).
6. **WebSocket / event subscription**: 5분 polling을 push로 대체하면 latency 감소.
7. **Read model rebuild 명령**: raw_chain_event 기반 truncate + replay.
8. **Admin Dashboard**: 운영 상태(cursor, job_run, lock), 수동 조작.

---

## 7. 우선순위 요약

| 순위 | 항목                        | 이유                    |
| ---- | --------------------------- | ----------------------- |
| P0   | S1 DB 비밀번호 평문         | 즉시 노출 위험          |
| P0   | S3 DUPLICATE_TX_HASH 미동작 | 실제 동작 버그          |
| P0   | D4 pre-bootstrap close 처리 | 전체 sync 정지 가능     |
| P1   | C1 event-sync 트랜잭션 범위 | snapshot R4와 같은 패턴 |
| P1   | C3 job_run STARTED stuck    | 운영 가시성 손상        |
| P1   | D1 reorg removed 처리       | 데이터 오염             |
| P1   | O1 RPC timeout/retry        | 운영 안정성             |
| P2   | C2 lock lease 연장          | 부하 증가 시            |
| P2   | O3 getLogs chunking         | catch-up 시나리오       |
| P2   | O7 pagination               | 데이터 누적 시          |
| P2   | S2/S5/S7 보안 정리          | 정보 누설/오용 방지     |
| P3   | D3 block timestamp          | 정확도                  |
| P3   | O6 메트릭/구조화 로깅       | 운영 성숙도             |
| P3   | T1/T2 테스트 보강           | 회귀 방지               |

---

## 관련 문서

- `release-risk-review.md` — 2026-05-08 시점 R1~R4 + D1~D3 (이미 일부 해결: R1 lock, R3 job_run, R4 snapshot)
- `decisions.md` — 결정 배경
- `data-retention-policy.md` — 보존 정책 (구현 완료)
- `scheduler-plan.md` — lock/lease 정책, safe-head 운영 정책
- `work-items.md` §F — 미결정 사항 (F1 중복 txHash 정책, F3 snapshot 부분 실패, F4 removed 처리, F7 RPC provider)
