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
