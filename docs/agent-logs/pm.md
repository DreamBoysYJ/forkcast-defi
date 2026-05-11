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

## 2026-05-10 — README 한국어 개편 초안 작성

### 작업 목적

백엔드가 추가된 현재 상태를 반영해, 루트 README를 어떤 방향으로 개편할지 한국어 초안으로 만든다.

### 읽은 파일

- `README.md`
- `README.ko.md`
- `web/README.md`
- `contracts/README.md`
- `contracts/src/README.md`
- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`
- `api-spec.md`
- `docs/frontend/backend-integration-plan.md`
- `docs/ops/README.md`
- `web/infra/cloud-run/README.md`

### 변경한 파일

- `docs/readme-draft.ko.md`
- `docs/agent-logs/pm.md`

### 한 일

- 기존 README를 덮어쓰지 않고, 별도 한국어 초안 파일을 추가했다.
- 컨트랙트 중심 dApp 설명을 유지하면서 Spring Boot 백엔드, 이벤트 인덱싱, read model, snapshot, scheduler/job lock/cursor 설계를 README 전면에 배치했다.
- 포트폴리오 관점에서 보여줄 역량을 별도 섹션으로 정리했다.

### 왜 그렇게 했는지

- 기존 README는 백엔드를 Future Work로 설명하고 있어 현재 구현 상태와 맞지 않는다.
- 취업/포트폴리오 용도에서는 단순 기능 나열보다 백엔드 책임 경계와 운영 설계 판단이 드러나는 편이 강하다.
- 사용자가 기존 내용을 지우라고 한 것은 아니므로, 직접 교체 전 검토 가능한 임시 초안으로 분리했다.

### 남은 문제

- 실제 루트 `README.ko.md`에 반영할 때는 기존 이미지, 라이브 데모, 발표 영상, 세부 Quick Start 문구를 얼마나 유지할지 결정해야 한다.
- 영어 README도 같은 구조로 맞출지, 한국어 README를 먼저 확정한 뒤 번역할지 결정이 필요하다.

## 2026-05-10 — 루트/백엔드/컨트랙트 README 분리 초안 작성

### 작업 목적

루트 README는 짧은 프로젝트 요약과 지원 분야별 입구로 만들고, 자세한 설명은 `backend/`, `contracts/` README로 분리하는 방향의 임시 초안을 만든다.

### 읽은 파일

- `README.md`
- `README.ko.md`
- `contracts/README.md`
- `contracts/src/README.md`
- `backend/build.gradle`
- `backend/src/main/resources/application.yaml`
- `backend/src/main/resources/db/migration/V1__init_schema.sql`
- `api-spec.md`
- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`

### 변경한 파일

- `README.ko.draft.md`
- `backend/README.ko.draft.md`
- `contracts/README.ko.draft.md`
- `docs/agent-logs/pm.md`

### 한 일

- 루트 초안은 기존 이미지와 라이브 데모 정보를 유지하면서, 전체 아키텍처와 지원 분야별 링크 중심으로 짧게 작성했다.
- 백엔드 초안은 Spring Boot 인덱서/조회 API, 데이터 모델, event-sync, snapshot, retry-safe 처리, scheduler/job lock/auth를 상세화했다.
- 컨트랙트 초안은 기존 컨트랙트 README의 내용을 한국어로 재구성하고, 백엔드와의 이벤트 연결 지점을 추가했다.

### 왜 그렇게 했는지

- 채용 담당자가 루트에서 전체 프로젝트를 빠르게 이해한 뒤, 지원 분야에 맞는 폴더 README로 들어가는 구조가 더 읽기 쉽다.
- 기존 루트 README는 컨트랙트 설명이 많고 백엔드는 Future Work처럼 남아 있어 현재 프로젝트 상태와 맞지 않는다.
- 기존 컨트랙트 README는 보존하면서, 한국어 포트폴리오용 설명을 별도 초안으로 검토할 수 있게 했다.

### 남은 문제

- `web/README.md`도 같은 톤의 한국어 상세 문서로 만들지 결정해야 한다.
- 실제 반영 시 `README.ko.md`, `backend/README.md`, `contracts/README.md` 중 어느 파일을 교체할지 결정해야 한다.
- 루트 이미지 alt text와 아키텍처 이미지 설명은 최종 문서에서 더 다듬을 수 있다.

## 2026-05-11 — README 초안 역할 분리 정리

### 작업 목적

루트 README 초안을 짧은 프로젝트 로비로 정리하고, 상세 설명은 각 폴더 README 초안으로 이동한다.

### 읽은 파일

- `readme-draft.ko.md`
- `backend/README.ko.draft.md`
- `contracts/README.ko.draft.md`
- `web/README.md`

### 변경한 파일

- `readme-draft.ko.md`
- `backend/README.ko.draft.md`
- `contracts/README.ko.draft.md`
- `web/README.ko.draft.md`
- `docs/agent-logs/pm.md`

### 한 일

- 루트 초안에서 컨트랙트/백엔드/프론트 상세 설명, 사용자 흐름 상세, 백엔드 API 목록, Local Development 명령을 제거했다.
- Live Demo 섹션을 3번으로 올렸다.
- 루트는 전체 소개, monorepo 구조, 아키텍처, 지원 분야별 링크, 짧은 스택 요약, 한계, 포트폴리오 관점만 남겼다.
- 웹 한국어 README 초안을 새로 만들고, wallet transaction flow, 백엔드 API 연동, build-time env 주의사항, address normalization, healthFactor sentinel 처리를 정리했다.
- 컨트랙트 README 초안에 기존 아키텍처 이미지와 StrategyLens 이미지를 추가하고, 디자인 결정 섹션을 보강했다.
- 백엔드 README 초안의 API 목록을 read model 출처가 보이는 표로 바꾸고, 로컬 DB 비밀번호 예시를 placeholder로 바꿨다.

### 왜 그렇게 했는지

- 루트 README는 채용 담당자가 지원 분야별 상세 문서로 들어가는 입구 역할을 해야 한다.
- 컨트랙트 모듈, 백엔드 설계, 프론트 연동 상세를 루트에 모두 두면 각 폴더 README의 목적이 흐려진다.
- Live Demo는 프로젝트 첫인상과 검증 가능성을 높이므로 상단에 배치하는 편이 낫다.

### 남은 문제

- 최종 채택 시 `.draft.md` 파일들을 실제 README 파일명으로 반영할지 결정해야 한다.
- 백엔드 README에는 아직 R1/R3/R4 retrospective 섹션을 추가할 여지가 있다.
- 루트 Mermaid를 PNG 다이어그램으로 교체할지 여부는 별도 결정이 필요하다.

## 2026-05-11 — 백엔드 README 회고 섹션 보강

### 작업 목적

백엔드 README 초안이 기능 카탈로그처럼 보이지 않도록, 실제 운영 리스크 발견과 개선 과정을 보여주는 회고 섹션을 추가한다.

### 읽은 파일

- `backend/README.ko.draft.md`
- `docs/backend/job-lock-r1-fix.md`
- `docs/backend/job-run-r3-fix.md`
- `docs/backend/snapshot-r4-fix.md`
- `docs/discussions/event-sync-window-policy.md`
- `docs/backend/release-risk-review.md`

### 변경한 파일

- `backend/README.ko.draft.md`
- `docs/agent-logs/pm.md`

### 한 일

- `Engineering Retrospectives` 섹션을 추가했다.
- R1 `job_lock` 안전화, R3 `job_run` 운영 이력 분리, R4 `snapshot` 트랜잭션 슬림화, event-sync window policy를 각각 4~6줄로 압축해 README에 노출했다.
- 각 회고 항목에서 원문 문서로 링크했다.
- Event Sync와 Snapshot Job 흐름을 더 짧은 요약 흐름으로 줄이고, 상세 회고 문서와 연결했다.
- API 표에 healthFactor sentinel, 중복 txHash, internal endpoint `202 SKIPPED` 같은 운영 디테일을 보강했다.
- 운영 문서 링크에 `release-risk-review.md`를 추가했다.

### 왜 그렇게 했는지

- 백엔드 포트폴리오에서 가장 강한 자산은 단순 구현 목록이 아니라, 실패 가능성을 발견하고 트랜잭션/락/스케줄링 경계를 고친 사고 과정이다.
- R1/R3/R4/window policy는 이미 별도 문서에 면접 답변 수준으로 정리되어 있었지만, README에서는 거의 보이지 않았다.
- README는 상세 문서의 입구 역할을 해야 하므로, 각 회고를 압축해 보여주고 원문으로 이어지게 했다.

### 남은 문제

- 필요하면 `docs/diagrams/diagram-backend.html`을 PNG로 캡처해 백엔드 README 상단에 추가할 수 있다.
- 최종 채택 전 `.draft.md` 파일명 정리 정책이 필요하다.

## 2026-05-11 — 영어 README 추가

### 작업 목적

현재 실제 한글 README(`README.md`, `backend/README.md`, `contracts/README.md`, `web/README.md`)를 기준으로 같은 구조의 영어 README를 추가한다.

### 읽은 파일

- `README.md`
- `backend/README.md`
- `contracts/README.md`
- `web/README.md`

### 변경한 파일

- `README.eng.md`
- `backend/README.eng.md`
- `contracts/README.eng.md`
- `web/README.eng.md`
- `docs/agent-logs/pm.md`

### 한 일

- 루트 영어 README를 새로 추가했다.
- 백엔드 영어 README를 새로 추가했다.
- 기존 오래된 컨트랙트/웹 영어 README를 현재 한글 README 기준으로 교체했다.
- 영어 문서의 내부 링크는 가능한 영어 README끼리 이어지도록 정리했다.

### 왜 그렇게 했는지

- 현재 루트와 폴더별 `README.md`가 한글판 기준 문서가 되었고, 기존 영어 문서는 백엔드 추가 전 내용이거나 현재 구조와 맞지 않았다.
- 한국어 문서와 동일한 포트폴리오 구조를 영어로도 제공해야 글로벌/영문 채용 문맥에서 바로 읽힐 수 있다.

### 남은 문제

- 최종적으로 오래된 `README.old.md`, `README.eng.old.md`, `README.ko.draft.md`, `docs/readme-draft.ko.md` 같은 임시/백업 문서의 보관 정책을 정해야 한다.
