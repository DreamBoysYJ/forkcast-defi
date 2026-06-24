# Forkcast DeFi - Claude Guide

## 목적

이 문서는 Claude Code가 이 레포에서 어떻게 일해야 하는지 알려주는 최상위 가이드다.

자세한 백엔드/프론트/QA 내용은 각 문서에서 확인한다.

## 이 레포의 성격 (취업 준비용)

이 레포는 **개발자 김영주의 취업 준비용 사이드 프로젝트**다.
개선 사안 논의, 채용 공고 요구조건 매칭, 스택 보강 방향을 함께 정할 때
개발자의 경력·스택·강점·공백을 알아야 한다.

매번 이력서/포트폴리오 PDF를 통째로 읽지 말고, 요약본을 참조한다:
- **`docs/candidate-profile.md`** — 경력 타임라인, 대표 프로젝트, 기술 스택, 강점/공백 요약
- 원본 PDF는 `get_jobs/` (필요할 때만 열 것)

## 프로젝트

Forkcast DeFi는 `contracts/`와 `web/`으로 구성된 DeFi monorepo다.

실제 구조:
```
forkcast-defi/
├── web/          # Next.js 프론트엔드
├── backend/      # Spring Boot 오프체인 인덱서
├── contracts/    # Foundry 스마트 컨트랙트
├── docs/         # 설계 문서, 운영 로그
└── api-spec.md   # 백엔드 API 명세
```

현재 목표는 기존 dApp에 Spring Boot 백엔드를 추가하고, 기존 프론트와 연결하는 것이다.

## 현재 상태 (2026-05)

- 프론트-백엔드 API 연동 5개 모두 완료 (상세: `docs/agent-logs/frontend.md`)
- 현재 브랜치: `release/v2`
- 백엔드 job lock, job run, snapshot 트랜잭션 hardening 완료 (R1~R4)

## 명령어

### Web (Next.js)
```bash
cd web && npm run dev    # 개발 서버 (localhost:3000)
cd web && npm run build
cd web && npm run lint
```

### Backend (Spring Boot)
```bash
cd backend && ./gradlew test
cd backend && ./gradlew bootRun
```
백엔드 실행 시 필수 환경 변수:
`RPC_URL`, `STRATEGY_ROUTER_ADDRESS`, `HOOK_ADDRESS`, `STRATEGY_LENS_ADDRESS`
로컬에서는 `SCHEDULER_AUTH_ENABLED=false`, `APP_CORS_ALLOWED_ORIGINS=http://localhost:3000` 추가

### Contracts (Foundry)
```bash
cd contracts && forge build
cd contracts && forge test
```

## 역할

- 사용자는 백엔드 구현 오너다.
- Claude는 백엔드 코드를 대신 대량 구현하지 않는다.
- Claude는 백엔드에서는 리뷰어/질문 답변자 역할을 한다.
- Claude는 프론트 연동 작업을 수행할 수 있다.
- Claude는 QA 시나리오와 테스트 초안을 작성할 수 있다.
- Claude는 작업을 문서화하고, 필요한 경우 작업 단위를 나눈다.

## 읽기 규칙

작업마다 필요한 문서만 읽는다.  
전체 repo를 처음부터 무작정 스캔하지 않는다.

### 백엔드 작업

먼저 읽기:

- `backend/README.md`
- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`

### 프론트 작업

먼저 읽기:

- `api-spec.md`
- `docs/backend/decisions.md`
- `docs/frontend/backend-integration-plan.md` 없으면 먼저 작성

그 다음 필요한 `web/` 파일만 읽는다.

### QA 작업

먼저 읽기:

- `api-spec.md`
- `docs/backend/data-model.md`
- `docs/backend/scheduler-plan.md`
- `docs/qa/test-scenarios.md` 없으면 먼저 작성

## 프론트 작업 원칙

- 기존 v1 UI와 디자인을 유지한다.
- 새 디자인을 임의로 만들지 않는다.
- 기존 컴포넌트와 스타일을 최대한 재사용한다.
- 기존 wallet transaction flow를 깨지 않는다.
- 백엔드 API 연결을 위한 최소 변경을 우선한다.
- 코드 수정 전에는 어떤 파일을 읽고 수정할지 계획을 먼저 남긴다.

## 백엔드 작업 원칙

- 백엔드 구현은 사용자가 직접 한다.
- Claude는 리뷰와 질문 답변 중심으로 돕는다.
- 사용자가 요청하지 않으면 백엔드 코드를 대량 생성하지 않는다.
- 리뷰 시 DB 정합성, unique, cursor, retry, job lock, 예외 처리를 중점적으로 본다.

## QA 작업 원칙

- API 성공/실패 케이스를 정리한다.
- pending tx, event-sync, snapshot, job lock 시나리오를 포함한다.
- 프론트-백엔드 연동 흐름도 검토한다.
- 테스트 코드 작성 전 테스트 시나리오 문서를 먼저 만든다.

## 작업 로그 규칙

의미 있는 작업 후에는 로그를 남긴다.

로그 위치:

- PM: `docs/agent-logs/pm.md`
- 백엔드 리뷰: `docs/agent-logs/backend-review.md`
- 프론트: `docs/agent-logs/frontend.md`
- QA: `docs/agent-logs/qa.md`
- Ops: `docs/agent-logs/ops.md`

로그에는 다음을 남긴다:

- 작업 목적
- 읽은 파일
- 변경한 파일
- 한 일
- 왜 그렇게 했는지
- 남은 문제

## 금지

- 전체 repo를 무작정 스캔하지 않는다.
- 기존 프론트 디자인을 임의로 갈아엎지 않는다.
- 백엔드가 유저 트랜잭션을 대신 보내는 구조로 바꾸지 않는다.
- 이미 합의한 백엔드 설계를 임의로 다시 열지 않는다.
- 역할별 의견만 말하고 파일 산출물을 남기지 않는 행동을 피한다.
