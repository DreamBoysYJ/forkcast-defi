# Backend Review Log

## 2026-05-04 — job lock 정상 종료 시 즉시 해제

### 작업 목적

`event-sync`와 `snapshot`이 정상 종료 또는 예외 종료 후에도 2분 lease가 남아 재실행이 막히는 문제를 수정한다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/job/domain/JobLock.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `backend/src/main/java/io/forkcast/backend/job/domain/JobLock.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `docs/backend/scheduler-plan.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `JobLock`에 즉시 만료 처리용 `releaseAt(now)`를 추가했다.
- `JobLockService`에 `release(jobName)`를 추가해서 lock row를 지우지 않고 `locked_until = now`로 즉시 해제하도록 했다.
- `event-sync`, `snapshot` 둘 다 lock 획득 후 실행한 경우에는 `finally`에서 항상 `release(jobName)`를 호출하도록 바꿨다.
- scheduler 문서에도 “정상 종료 시 즉시 release, crash 시 lease expiry로 복구” 원칙을 메모했다.

### 왜 그렇게 했는지

- 기존 구현은 lease-based acquire만 있고 정상 종료 시 release가 없어서, job이 몇 초 만에 끝나도 `locked_until`이 남아 있는 동안 `already running`으로 `SKIPPED` 됐다.
- lock의 본래 의도는 “실행 중 동시 실행 방지 + crash 시 자동 복구”이지, “정상 종료 후 lease 만료까지 재실행 금지”가 아니다.
- row 삭제 대신 `locked_until = now`로 해제하면 현재 테이블 구조를 유지하면서 즉시 재획득이 가능하다.

### 남은 문제

- 현재 lease duration은 `Duration.ofMinutes(2)` 하드코딩이다. 운영에서는 job 최대 실행시간에 맞게 설정값 분리가 필요할 수 있다.
- 장기적으로 job 실행시간이 lease보다 길어질 수 있으면 extend/heartbeat 전략도 검토할 수 있다.

## 2026-05-04 — tx hint 저장 인자 순서 수정

### 작업 목적

`POST /api/tx-hints` 요청을 받을 때 `actionType`과 `userAddress`가 뒤바뀌어 저장될 수 있는 버그를 바로잡는다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/txHint/controller/PendingTxController.java`
- `backend/src/main/java/io/forkcast/backend/txHint/service/PendingTxService.java`
- `backend/src/main/java/io/forkcast/backend/txHint/domain/PendingTx.java`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `backend/src/main/java/io/forkcast/backend/txHint/controller/PendingTxController.java`
- `docs/agent-logs/backend-review.md`

### 한 일

- `PendingTxController`에서 `pendingTxService.create(...)` 호출 인자 순서를 service 시그니처에 맞게 수정했다.
- 그 결과 `pending_tx.action_type`에는 실제 `actionType`, `pending_tx.user_address`에는 실제 `userAddress`가 저장되도록 바로잡았다.

### 왜 그렇게 했는지

- 기존 코드는 controller에서 `create(txHash, userAddress, actionType)` 순서로 넘기고 있었지만, service 시그니처는 `create(txHash, actionType, userAddress)`였다.
- 이 상태로는 `pending_tx`에 값이 바뀌어 들어가서 이후 pending UX, 상태 조회, reconcile 작업을 붙일 때 데이터 의미가 깨질 수 있다.

### 남은 문제

- 현재 `pending_tx`는 생성 API만 있고, 프론트에 다시 보여주는 조회 API나 event-sync 기반 상태 reconcile 로직은 아직 연결되지 않았다.
- 2026-05-04 기준 이 reconcile은 v1 scope 밖으로 두고, 최종 truth는 계속 on-chain / read model로 본다.

## 2026-05-04 — event-sync 최초 bootstrap 범위 축소

### 작업 목적

클라우드 첫 배포 시 `event-sync`가 cursor 부재 상태에서 제네시스부터 최신 세폴리아까지 한 번에 스캔하지 않도록, 최초 bootstrap 범위를 최근 safe window로 제한한다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/sync/config/SyncProperties.java`
- `backend/src/main/resources/application.yaml`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/sync/config/SyncProperties.java`
- `backend/src/main/resources/application.yaml`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `sync.bootstrap-window-blocks` 설정을 추가하고 기본값을 `25`로 두었다.
- `event-sync` 첫 실행 시 cursor가 없으면 `0`이 아니라 `safeHead - bootstrapWindowBlocks` 근처에서 cursor를 생성하도록 바꿨다.
- 그 결과 첫 클라우드 실행은 최근 safe window만 읽고, 이후 실행부터는 일반 cursor 전진 로직을 그대로 사용한다.
- 운영 문서에도 "first bootstrap does not start from genesis" 정책을 반영했다.

### 왜 그렇게 했는지

- 기존 로직은 DB가 비어 있는 첫 배포에서 `fromBlock = 1`, `toBlock = latestBlock - 5`가 되어 Sepolia 전체 범위를 한 번에 조회하려고 했다.
- address/topic 필터가 있더라도 첫 `eth_getLogs` 범위가 너무 크면 RPC timeout, provider range limit, 긴 cold start를 유발할 수 있다.
- 이 서비스의 v1 운영 모델은 "배포 이후 활동부터 따라가기"에 가깝기 때문에, 최초에 최근 safe 구간만 bootstrap해도 충분하다.

### 남은 문제

- bootstrap window `25`는 block 기준 기본값이다. 실제 운영에서 더 짧게/길게 가져갈지는 배포 후 RPC 응답성과 사용자 활동 패턴을 보고 조정할 수 있다.
- 배포 이전 과거 이벤트를 복원해야 하는 별도 요구가 생기면, bootstrap 정책과 별도로 backfill 전략을 따로 마련해야 한다.
- `event_timestamp = Instant.now()` 선택은 당시 ingest/decode/save 경로를 먼저 안정화하기 위한 임시 선택이었다. 정확한 block timestamp가 중요해지면 block 조회/cache를 붙여 개선할 수 있다.

## 2026-05-01 — position snapshot 조회 API 추가

### 작업 목적

내부 `snapshot` job이 적재한 `position_snapshot` 데이터를 외부 조회 API로 노출해서, 스냅샷이 저장 전용 상태에 머물지 않게 한다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/snapshot/controller/SnapshotController.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/domain/PositionSnapshot.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/repository/PositionSnapshotRepository.java`
- `backend/src/main/java/io/forkcast/backend/position/controller/OpenPositionController.java`
- `backend/src/main/java/io/forkcast/backend/position/controller/PositionTimelineController.java`
- `backend/src/main/java/io/forkcast/backend/position/service/OpenPositionQueryService.java`
- `backend/src/main/java/io/forkcast/backend/position/dto/OpenPositionResponse.java`
- `backend/src/main/java/io/forkcast/backend/position/dto/PositionTimelineResponse.java`

### 변경한 파일

- `backend/src/main/java/io/forkcast/backend/snapshot/controller/PositionSnapshotController.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/PositionSnapshotQueryService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/dto/PositionSnapshotResponse.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/repository/PositionSnapshotRepository.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/domain/PositionSnapshot.java`
- `api-spec.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `GET /api/positions/{tokenId}/snapshots?limit=20` 외부 조회 API를 추가했다.
- `position_snapshot`를 `snapshot_at desc`로 읽는 repository 메서드와 query service를 만들었다.
- 응답 DTO에서 256-bit 정수/decimal 계열 값을 모두 string으로 변환해서 JSON 정밀도 손실을 피했다.
- 기존 `PositionSnapshotRepository`에 있던 잘못된 `findByIsOpenTrue()` 선언을 제거하고, 실제 조회 경로에 맞는 메서드로 정리했다.
- `api-spec.md`에 snapshot 조회 API 목적, 응답 shape, 주의사항을 문서화했다.
- 실제 Sepolia `StrategyLens.getUserAaveOverview(user)`를 JSON-RPC `eth_call`로 확인했고, debt가 0인 포지션은 `healthFactor = uint256 max` sentinel을 반환하는 것을 검증했다.
- snapshot 저장 로직에서 sentinel / overflow 성격의 `healthFactor`는 저장 가능한 최대 finite 값으로 요약해서 job 전체 실패를 막도록 보정했다.

### 왜 그렇게 했는지

- 현재 상태는 snapshot job이 데이터를 쌓기만 하고 프론트나 외부 API가 읽지 못하는 반쪽 구현에 가까웠다.
- snapshot 값들은 `BigInteger`/`BigDecimal` 비중이 높아서, 숫자 그대로 JSON에 내리면 프론트에서 정밀도 손실 위험이 크다.
- per-position 히스토리 조회 하나만 먼저 열어도, 이후 모달/상세 화면에서 snapshot 의도를 검증하기가 쉬워진다.
- `healthFactor`는 no-debt 포지션에서 사실상 무한대 의미를 가질 수 있어서, sentinel 값을 그대로 DB numeric 컬럼에 넣으면 snapshot job 전체가 죽는다.

### 남은 문제

- 아직 snapshot API를 실제 프론트 화면에 연결하지 않았다.
- `tokenId`가 존재하지만 snapshot row가 아직 없는 경우를 별도 `404`로 구분하지 않고 빈 배열로 응답한다.
- 통합 테스트는 아직 남아 있다.

## 2026-04-30 — event-sync web3j decode/raw save 정리

### 작업 목적

`event-sync` 최소 경로에서 중복 decoder를 정리하고, 실제 RPC 조회 결과를 decode해서 `raw_chain_event`까지 저장되도록 연결한다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/chain/client/EventLogDecoder.java`
- `backend/src/main/java/io/forkcast/backend/chain/service/RawChainEventService.java`
- `backend/src/main/java/io/forkcast/backend/sync/client/Web3jChainClient.java`
- `backend/src/main/java/io/forkcast/backend/sync/config/SyncProperties.java`
- `backend/src/main/resources/application.yaml`

### 변경한 파일

- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/resources/application.yaml`
- `docs/backend/decisions.md`
- `docs/agent-logs/backend-review.md`

### 삭제한 파일

- `backend/src/main/java/io/forkcast/backend/sync/decoder/EventLogDecoder.java`
- `backend/src/main/java/io/forkcast/backend/sync/decoder/DecodedEvent.java`
- `backend/src/main/java/io/forkcast/backend/sync/client/EthRpcClient.java`

### 한 일

- `EventSyncService`에서 예전 `EthRpcClient`와 `sync.decoder.*` 의존성을 제거했다.
- `chain.client.EventLogDecoder`와 `RawChainEventService`를 주입해서, router/hook 로그를 읽은 뒤 바로 decode + `raw_chain_event` 저장까지 수행하게 했다.
- router topic 목록의 오타를 수정해서 `PositionOpened`, `PositionClosed`, `FeesCollected`를 올바르게 조회하도록 맞췄다.
- router/hook 로그를 합쳐 block/log index 순으로 정렬한 뒤 처리하게 했다.
- `application.yaml`의 설정 prefix를 `sync.*`로 바로잡아 `SyncProperties` 바인딩이 실제로 되도록 수정했다.
- 문서와 코드가 다시 어긋나지 않게 `decisions.md`의 v1 chain access 결정을 `web3j` 기준으로 갱신했다.

### 왜 그렇게 했는지

- decode 경로가 두 벌로 남아 있으면 다음 단계에서 어떤 클래스를 기준으로 이어가야 할지 계속 흔들린다.
- 지금 단계 목표는 projection이 아니라 “로그를 읽고 raw event를 쌓는 것”이므로, 최소 연결만 먼저 끝내는 편이 맞다.
- 설정 prefix가 틀린 상태에서는 코드가 맞아도 RPC URL과 컨트랙트 주소가 런타임에 비어 버린다.
- router와 hook를 따로 읽더라도 저장 순서는 block/log index 순이 더 자연스럽고, 이후 조회용 테이블 업데이트를 붙일 때도 덜 헷갈린다.

### 남은 문제

- `raw_chain_event.event_timestamp`는 아직 `Instant.now()` 임시값이다. 정확히 하려면 block timestamp 조회가 추가로 필요하다.
- 조회용 테이블(`strategy_position`, `position_timeline`, `pool_price_event`) 업데이트는 아직 연결하지 않았다.
- `Web3jChainClient` 패키지 위치를 `sync/client`에 둘지 `chain/*` 쪽으로 옮길지는 나중에 한 번 더 정리할 수 있다.

## 2026-05-08 — release risk review 정리

### 작업 목적

현재 통합된 백엔드 코드를 기준으로, 배포 전에 다시 봐야 할 위험 지점과 이후 최적화 우선순위를 문서로 고정한다.

### 읽은 파일

- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobRunService.java`
- `backend/src/main/java/io/forkcast/backend/position/service/StrategyPositionService.java`
- `backend/src/main/java/io/forkcast/backend/position/service/PositionTimelineService.java`
- `backend/src/main/java/io/forkcast/backend/chain/service/RawChainEventService.java`
- `backend/src/main/resources/db/migration/V1__init_schema.sql`

### 변경한 파일

- `docs/backend/release-risk-review.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- 배포 전 리스크를 `release blocker`, `high-priority operational risk`, `known debt`, `later optimization`으로 나눠 정리했다.
- 핵심 위험으로 아래 4가지를 문서에 남겼다:
  - `job_lock`가 같은 트랜잭션 안에서 잡혀 운영 동시 실행 방어가 약한 점
  - bootstrap 이전 포지션의 close/fees 이벤트가 들어오면 `event-sync`가 반복 중단될 수 있는 점
  - 실패한 `job_run` 이력이 rollback으로 사라질 수 있는 점
  - `snapshot`이 모든 오픈 포지션을 하나의 긴 트랜잭션으로 처리하는 점
- 이후 최적화 후보로 `exists + save` 패턴, ingest 시각 기반 `event_timestamp`, 테스트 부족도 함께 묶어뒀다.
- 다음 작업 순서를 문서 안에 단계별로 적어뒀다.

### 왜 그렇게 했는지

- 지금 단계에서는 막연히 “위험해 보인다”로 남겨두기보다, 배포 차단 이슈와 나중 debt를 분리해야 우선순위 판단이 가능하다.
- 특히 `job_lock`, `cursor`, `legacy position` 문제는 운영에서 한 번 터지면 기능 추가보다 복구가 더 어려운 종류라 먼저 가시화할 가치가 있다.

### 남은 문제

- 아직 코드 수정은 하지 않았고, 리뷰 결과만 문서화한 상태다.
- `close/fees`의 missing position 정책은 팀 결정이 더 필요하다.
- lock acquire 방식을 어떤 SQL 패턴으로 바꿀지는 구현 시점에 다시 구체화해야 한다.

## 2026-05-08 — release risk review 보정 메모

### 작업 목적

문서에 적어둔 R2 위험도를 현재 운영 가정에 맞게 더 현실적으로 보정한다.

### 읽은 파일

- `docs/backend/release-risk-review.md`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `docs/backend/release-risk-review.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- R2(`pre-bootstrap close/fee events`)에 현재 배포 가정을 추가로 적었다.
- 현재 범위에서는 "배포 이후 생성 포지션만 운영상 의미 있다"는 전제가 강하면, 이 리스크의 즉시성은 낮다고 메모했다.
- 다만 그 전제가 깨지면 다시 blocker가 될 수 있으므로, 일반론 리스크 자체는 문서에 그대로 남겨뒀다.

### 왜 그렇게 했는지

- 코드 일반론과 현재 운영 범위를 분리해서 봐야 실제 우선순위를 잘못 올리지 않는다.
- 이번 프로젝트처럼 초기 사용 범위가 좁을 때는 historical position 처리 리스크가 당장 현실화되지 않을 수 있다.

### 남은 문제

- 이 판단은 "배포 이후 생성 포지션만 의미 있다"는 운영 전제가 유지될 때만 유효하다.
- 향후 pre-existing position을 다루게 되면 R2는 다시 높은 우선순위로 올라온다.

## 2026-05-08 — job_lock R1 테스트 추가

### 작업 목적

`job_lock` R1 수정이 실제로 기대한 동작을 하는지 가장 작은 통합 테스트로 확인한다.

### 읽은 파일

- `backend/build.gradle`
- `backend/src/main/resources/application.yaml`
- `backend/src/main/java/io/forkcast/backend/job/repository/JobLockRepository.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/config/SyncProperties.java`
- `backend/src/main/java/io/forkcast/backend/sync/config/Web3jConfig.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/client/StrategyLensClient.java`

### 변경한 파일

- `backend/src/test/java/io/forkcast/backend/job/service/JobLockServiceTest.java`
- `docs/agent-logs/backend-review.md`

### 한 일

- `JobLockService` 기준 통합 테스트 클래스를 추가했다.
- 첫 acquire 성공 후 lease가 살아있는 동안 두 번째 acquire가 실패하는 케이스를 검증했다.
- owner가 다른 release는 락을 풀지 못하고, owner가 같은 release만 락을 푼다는 점을 검증했다.
- `./gradlew test --tests io.forkcast.backend.job.service.JobLockServiceTest` 실행으로 테스트 통과를 확인했다.

### 왜 그렇게 했는지

- 이번 수정은 단순 자바 로직보다 `ON CONFLICT` 쿼리, `REQUIRES_NEW`, `locked_by` 조건이 핵심이라 mock보다 실제 DB를 타는 통합 테스트가 더 맞다.
- 멀티스레드 테스트까지 가지 않아도, 이번 R1의 핵심 계약을 작게 고정해두는 것만으로 회귀 방지 효과가 크다.

### 남은 문제

- 아직 `event-sync`와 `snapshot` 엔드투엔드 동시 실행 테스트는 없다.
- lease 만료 후 재획득 동작까지 별도 테스트로 고정해두면 더 좋다.

## 2026-05-08 — job_lock R1 설명 문서 추가

### 작업 목적

`job_lock` R1 이슈와 수정 이유를 나중에 다시 봐도 바로 이해할 수 있게 별도 설명 문서로 남긴다.

### 읽은 파일

- `docs/backend/release-risk-review.md`
- `backend/src/main/java/io/forkcast/backend/job/repository/JobLockRepository.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/test/java/io/forkcast/backend/job/service/JobLockServiceTest.java`

### 변경한 파일

- `docs/backend/job-lock-r1-fix.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `job_lock` R1 문제를 별도 문서로 정리했다.
- 문제 상황, 원인, `REQUIRES_NEW`가 필요한 이유, `ON CONFLICT` acquire 쿼리 의미, UUID owner가 필요한 이유, release 의미를 한 문서에 모았다.
- 이번 수정이 무엇을 해결하고 무엇은 아직 안 해결하는지도 함께 적었다.

### 왜 그렇게 했는지

- 이번 수정은 코드 몇 줄보다 개념이 더 헷갈리기 쉬운 종류라, 나중에 다시 봤을 때 배경까지 한 번에 이어지는 문서가 필요했다.
- release owner, lease 만료, 별도 커밋 경계 같은 포인트는 구두 설명만으로는 쉽게 잊힌다.

### 남은 문제

- 현재 문서는 R1 중심 설명 문서라 `R3`, `R4`의 후속 설계까지는 다루지 않는다.

## 2026-05-08 — job_lock R1 설명 문서 한글화

### 작업 목적

`docs/backend/job-lock-r1-fix.md`를 한국어로 바꿔서 이후 재확인할 때 더 빠르게 읽히게 만든다.

### 읽은 파일

- `docs/backend/job-lock-r1-fix.md`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `docs/backend/job-lock-r1-fix.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `job_lock` R1 설명 문서의 제목과 본문을 전부 한국어로 옮겼다.
- 기존 구조는 유지하되, 문제 상황, 원인, `REQUIRES_NEW`, `ON CONFLICT`, UUID owner, release 의미가 자연스럽게 읽히도록 표현을 다듬었다.

### 왜 그렇게 했는지

- 이 문서는 구현 코드를 고치는 순간보다, 나중에 다시 배경을 떠올릴 때 더 자주 쓰일 가능성이 높다.
- 영어보다 한글이 빠르게 들어오도록 바꿔두는 편이 실제 유지보수에 더 도움이 된다.

### 남은 문제

- 내용은 한글화되었지만, 이후 설계가 더 바뀌면 문서도 함께 업데이트해야 한다.

## 2026-05-08 — job_run R3 설명 문서 추가

### 작업 목적

`job_run` 실패 이력 롤백 문제를 면접이나 복습 때 바로 설명할 수 있도록 별도 한글 문서로 정리한다.

### 읽은 파일

- `backend/src/main/java/io/forkcast/backend/job/service/JobRunService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/test/java/io/forkcast/backend/job/service/JobRunServiceTest.java`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `docs/backend/job-run-r3-fix.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `job_run` R3 문제를 복습용 문서로 따로 정리했다.
- 문제 발견 배경, 기존 트랜잭션 구조, 왜 `markFailed()`만 `REQUIRES_NEW`로는 부족한지, 최종 수정 방향, 테스트 검증 내용을 한 문서에 모았다.
- 마지막에는 면접에서 짧게 말할 수 있는 답변 형태도 함께 적어뒀다.

### 왜 그렇게 했는지

- 이번 문제는 코드 diff보다 "왜 이렇게 바꿔야 하는가"를 설명하는 능력이 더 중요하다.
- 면접이나 회고에서는 발견 과정과 원인 분석, 검증 방식까지 한 흐름으로 설명할 수 있어야 한다.

### 남은 문제

- 현재 문서는 R3 중심이라 `R4` 같은 다음 운영 리스크까지는 다루지 않는다.

## 2026-05-08 — snapshot R4 설명 문서와 테스트 추가

### 작업 목적

`snapshot` job의 긴 트랜잭션 / 부분 실패 문제(`R4`)를 복습용 문서로 정리하고, 새 구조가 실제로 부분 실패를 허용하는지 테스트로 확인한다.

### 읽은 파일

- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotWriteService.java`
- `backend/src/test/java/io/forkcast/backend/snapshot/service/SnapshotServiceTest.java`
- `docs/agent-logs/backend-review.md`

### 변경한 파일

- `docs/backend/snapshot-r4-fix.md`
- `docs/agent-logs/backend-review.md`

### 한 일

- `snapshot` R4 문제를 별도 한글 문서로 정리했다.
- 왜 긴 트랜잭션이 문제였는지, 왜 이번 단계에서는 chunk보다 `collect all + saveAll`을 택했는지, 왜 `SnapshotWriteService`를 따로 만들었는지를 문서에 적었다.
- `SnapshotServiceTest`로 "한 포지션 RPC 성공, 한 포지션 RPC 실패" 시나리오에서 성공한 snapshot만 저장되고 job 자체는 성공 처리되는지를 검증했다.
- `./gradlew test --tests io.forkcast.backend.snapshot.service.SnapshotServiceTest` 실행으로 테스트 통과를 확인했다.

### 왜 그렇게 했는지

- 이번 문제는 단순히 코드를 바꾼 것보다 "실패 범위를 어떻게 줄였는가"를 설명할 수 있어야 의미가 있다.
- 면접이나 회고에서는 기술 선택의 이유와 trade-off를 같이 말할 수 있어야 하므로, 설명 문서와 테스트를 함께 남기는 편이 좋다.

### 남은 문제

- 현재 문서는 `collect all + saveAll` 기준 1차 해결 정리라, 향후 포지션 수가 크게 늘면 chunk/병렬화 재검토가 필요할 수 있다.
