# Ops Agent Log

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
