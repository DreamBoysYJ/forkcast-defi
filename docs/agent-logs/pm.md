# PM Log

## 2026-04-23 — work-items.md 역할별 재구성

### 작업 목적

기존 `docs/backend/work-items.md`는 phase 중심으로 백엔드 코딩 작업만 다루고 있었다.
사용자 요청에 따라 작업을 더 작은 단위로 쪼개고, 다음 4개 역할로 분류했다.

- 사용자 직접 백엔드 작업
- Claude가 맡을 프론트 작업
- Claude가 맡을 QA 작업
- Claude가 맡을 Ops 문서 작업

각 작업에 선행 조건, 산출물, 완료 기준을 명시했다.

### 읽은 파일

- `CLAUDE.md` (시스템 컨텍스트로 제공)
- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `api-spec.md` (루트 — `docs/backend/api-spec.md`가 아님)
- `docs/backend/work-items.md` (기존 phase 기반 초안)
- `docs/backend/test-scenarios.md`
- `docs/agent-logs/`, `docs/frontend/`, `docs/qa/`, `docs/ops/` 비어 있음 확인

코드 디렉토리(`web/`, `contracts/`)는 의도적으로 스캔하지 않았다 (CLAUDE.md 규칙).

### 변경한 파일

- `docs/backend/work-items.md` — 역할 4분류 + 선행 조건/산출물/완료 기준/의존성/미결정 사항 포함하여 전면 재작성
- `docs/agent-logs/pm.md` — 본 로그 신규 작성

### 한 일

- 기존 백엔드 phase 작업을 23개의 사용자 직접 작업(A1~A23)으로 재배열했다.
  - DB 마이그레이션을 단일 항목(A3)으로 묶고, JPA 엔티티는 운영/힌트(A4) vs read model(A5)로 분할했다.
  - 프로젝션을 Router(A11)와 Hook(A12)로 분리했다.
  - 외부 API 5개를 각각 별도 항목(A17~A21)으로 분리했다.
- Claude 프론트 작업(B1~B8)을 신설했다.
  - 가장 먼저 `docs/frontend/backend-integration-plan.md`를 작성하도록 B1을 선행 작업으로 둠 (CLAUDE.md의 "프론트 작업 전 계획 먼저" 규칙 반영).
  - 기존 디자인/지갑 흐름 보존을 모든 프론트 항목에 명시.
- Claude QA 작업(C1~C7)을 신설했다.
  - 기존 `test-scenarios.md` 보완(C1)을 가장 먼저 둠.
  - 통합 시나리오, pending tx UX, event-sync 리커버리, snapshot 실패 매트릭스, 스키마 체크리스트, 보안 시나리오로 분리.
- Claude Ops 문서 작업(D1~D6)을 신설했다.
  - 런북, Cloud Run config, Cloud Scheduler, observability, DB ops, 인시던트 플레이북.
- 의존성(E)과 미결정 사항(F)을 명시해 다음 단계 의사결정을 모았다.

### 왜 그렇게 했는지

- **역할 우선 분류**: 사용자가 백엔드 오너이고 Claude는 리뷰어/프론트/QA/Ops 헬퍼라는 CLAUDE.md 원칙을 work-items 레벨에서도 그대로 반영하기 위함. 한 문서 안에서 누가 무엇을 하는지 즉시 보이도록 함.
- **작업 단위 세분화**: 기존 phase는 합리적이지만 phase 단위로 PR을 묶기엔 너무 컸다. 23개 단위로 쪼개면 PR/리뷰 회전과 우선순위 조정이 쉬워진다.
- **선행/산출물/완료 기준 의무화**: "리뷰어가 PR을 받았을 때 무엇을 검증할지"를 작업 정의 단계에서 못박으면, 사용자가 코딩하면서 빠뜨리는 것이 줄어든다.
- **C1을 가장 먼저**: `test-scenarios.md`가 이미 충실하므로, 신규 시나리오를 새로 만들기 전에 결정 미정 항목을 먼저 닫는 것이 효율적이다.
- **F 섹션**: 결정이 필요한 항목을 한곳에 모아 사용자가 한 번에 처리할 수 있게 했다. 결정되지 않으면 코드와 시나리오가 어긋날 수 있다.

### 남은 문제

- **api-spec.md 위치 불일치**: CLAUDE.md는 `docs/backend/api-spec.md`를 참조하지만 실제 파일은 루트 `api-spec.md`에 있다. work-items F5에 기록. 사용자가 어느 쪽으로 통일할지 결정 후 일관화 필요.
- **미결정 사항 7건(F1~F7)**: 결정될 때까지 관련 작업의 완료 기준이 잠정 상태로 남는다.
- **백엔드 모듈 디렉토리명/구조**: A1에서 사용자 합의 필요. 본 문서에서는 `backend/`로 가정만 했다.
- **인증 방식 세부**: A22와 D2/D3가 OIDC 또는 시크릿 헤더로 어떻게 결합되는지 사용자가 결정해야 한다.
- **frontend/qa/ops 폴더 비어 있음**: B/C/D 작업이 시작되면서 채워질 예정. 이 PM 로그는 그 시점에도 인덱스 역할을 하게 유지할 것.

## 2026-04-30 — event-sync window policy 문서화

### 작업 목적

`event-sync`의 스케줄 주기와 block range 계산 규칙에 대해 논의한 내용을 문서로 남기고, 기존 문서 간 충돌을 정리한다.

핵심 질문은 다음이었다.

- Cloud Scheduler가 block range를 정하는가?
- 백엔드는 최신 블록까지 읽어야 하는가?
- 1분 vs 5분 중 어떤 주기가 v1에 맞는가?
- reorg 대응을 위해 rewind/rebuild를 지금 넣어야 하는가?

### 읽은 파일

- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `docs/agent-logs/pm.md`

### 변경한 파일

- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `docs/discussions/event-sync-window-policy.md`
- `docs/agent-logs/pm.md`

### 한 일

- `docs/discussions/` 폴더 성격의 첫 문서로 `event-sync-window-policy.md`를 추가했다.
- 토론 문서에는:
  - 문제 배경
  - 시스템 현실
  - 선택지 A/B/C
  - 1분 vs 5분 논의
  - 최종 v1 결정
  - 의도적으로 하지 않는 것
  을 남겼다.
- `scheduler-plan.md`에서 `event-sync` 초기 주기를 `1 minute`에서 `5 minutes`로 수정했다.
- 같은 문서에 “Cloud Scheduler는 trigger만 하고, block range는 backend가 계산한다”는 책임 분리를 명시했다.
- `latestBlock - 5` safe-head 규칙과 `lastSyncedBlock + 1` 시작 규칙을 `scheduler-plan.md`에 추가했다.
- `decisions.md`의 기존 “1분 시작” 결정을 “5분 + safe head” 정책으로 갱신했다.

### 왜 그렇게 했는지

- **문서 충돌 제거**: 기존 문서는 `event-sync` 1분 기준이어서, 최근 합의와 정면 충돌했다. 설계 문서는 현재 합의와 같아야 이후 구현/리뷰가 흔들리지 않는다.
- **토론과 결정 분리**: `decisions.md`는 짧은 결론을 남기기에 좋지만, 왜 다른 선택지를 버렸는지 맥락은 담기 어렵다. 그래서 `docs/discussions/`에 별도 논의 문서를 두었다.
- **책임 경계 명확화**: 사용자가 짚은 대로, Cloud Scheduler는 “언제 호출할지”만 정하고 “몇 번 블록부터 몇 번 블록까지 읽을지”는 백엔드가 정한다. 이 구분을 문서에 못박아야 구현이 단순해진다.
- **v1 단순성 우선**: overlap rewind, recent-range rebuild, receipt watcher 같은 대안은 모두 가능하지만 지금 단계에선 복잡도를 크게 올린다. `cursor + 1`부터 `latest - 5`까지 읽는 정책이 가장 설명 가능하고 운영하기 쉽다.

### 남은 문제

- `pending_tx`와 최종 read model 사이 UX 기대치는 아직 별도 문서로 정리하지 않았다.
- `safeHead = latestBlock - 5`의 `5`를 설정값으로 뺄지 하드코딩으로 시작할지는 추후 구현 시점 결정이 필요하다.
- 추후 실제 RPC 사용량과 sync lag를 본 뒤 `5분` 주기와 `-5블록` 정책을 다시 조정할 수 있다.

## 2026-04-30 — v1 RPC 방식 결정 추가

### 작업 목적

백엔드 체인 접근 방식을 짧게 설계 문서에 남긴다.

### 읽은 파일

- `docs/backend/decisions.md`
- `docs/agent-logs/pm.md`

### 변경한 파일

- `docs/backend/decisions.md`
- `docs/agent-logs/pm.md`

### 한 일

- `decisions.md`에 v1에서는 `web3j`를 먼저 도입하지 않고 direct JSON-RPC로 시작한다는 결정을 추가했다.
- v1에서 사용하는 RPC 범위를 `eth_blockNumber`, `eth_getLogs`, `eth_call` 3종으로 짧게 명시했다.

### 왜 그렇게 했는지

- 현재 범위에서는 라이브러리 도입보다 구현 단순성과 디버깅 용이성이 더 중요하다.
- `event-sync`와 `snapshot`에 필요한 RPC 종류가 아직 작아서 직접 JSON-RPC로도 충분하다.

### 남은 문제

- `eth_call`의 ABI encode/decode가 늘어나면 이후 `web3j` 재검토 여지는 남아 있다.

## 2026-05-01 — Scheduler 인증 방식 문서화

### 작업 목적

내부 job endpoint를 어떤 방식으로 보호할지 합의된 내용을 짧게 남긴다.

### 읽은 파일

- `docs/backend/decisions.md`
- `docs/backend/scheduler-plan.md`
- `docs/agent-logs/pm.md`

### 변경한 파일

- `docs/backend/decisions.md`
- `docs/backend/scheduler-plan.md`
- `docs/agent-logs/pm.md`

### 한 일

- `decisions.md`에 v1에서는 서비스를 나누지 않고 현재 API 구조를 유지한다는 점을 추가했다.
- 같은 문서에 `/internal/jobs/**`만 앱 코드에서 Google OIDC Bearer token으로 검증한다는 결정을 추가했다.
- `scheduler-plan.md`의 auth 섹션을 실제 선택안 기준으로 정리했다.
  - Scheduler 전용 service account 사용
  - expected audience 검사
  - allowed service account email 검사
  - `/api/**`는 공개 유지
  - 로컬에서는 설정으로 auth off 가능

### 왜 그렇게 했는지

- 지금 단계에서는 서비스 분리보다 현재 구조 유지가 우선이다.
- 내부 job만 막고 공개 조회 API는 열어둬야 해서 앱 레벨 보호가 가장 작은 변경이다.
- User-Agent, IP, 고정 secret보다 OIDC service account 검증이 운영 기준으로 더 명확하다.

### 남은 문제

- 실제 env 이름과 기본값은 구현 코드와 함께 최종 고정해야 한다.
- 스테이징에서 Cloud Scheduler OIDC 설정과 backend audience 값이 정확히 맞는지 한 번 더 확인해야 한다.
