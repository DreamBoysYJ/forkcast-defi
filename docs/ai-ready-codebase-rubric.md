# AI-Ready Codebase Rubric, 100점

이 문서는 임의의 코드베이스가 AI 코딩 에이전트와 협업하기에 얼마나 준비되어 있는지 평가하기 위한 기준표다.

목적은 "좋은 코드인가"를 추상적으로 평가하는 것이 아니라, AI가 짧은 시간 안에 다음을 할 수 있는지를 보는 것이다.

- 어디를 읽어야 하는지 찾는다.
- 변경 영향 범위를 추적한다.
- 숨은 운영 규칙과 실패 패턴을 이해한다.
- 스스로 검증하고 안전하게 작업을 마무리한다.

## Summary

| Category | Points | What It Measures |
| --- | ---: | --- |
| A. AI Navigation & Coverage | 15 | AI가 전체 codebase/module/workflow를 빠르게 찾을 수 있는가 |
| B. Context Document Quality | 20 | context 문서가 "compass, not encyclopedia" 원칙을 따르는가 |
| C. Tribal Knowledge Externalization | 20 | 숨은 규칙, 실패 패턴, human-only knowledge가 구조화되어 있는가 |
| D. Cross-Module Dependency & Data Flow Mapping | 15 | 변경 영향 범위를 AI가 추적할 수 있는가 |
| E. Verification & Quality Gates | 15 | AI-generated context와 code changes를 검증하는 체계가 있는가 |
| F. Freshness & Self-Maintenance | 10 | context가 stale해지지 않도록 유지되는가 |
| G. Agent Performance Outcomes | 5 | 실제 AI task 성공률/효율 개선이 측정되는가 |

## Scoring Rule

- 각 항목은 부분 점수를 줄 수 있다.
- 문서가 존재하는 것보다, 실제 작업자가 1~2 hops 안에 필요한 결정을 찾을 수 있는지가 중요하다.
- 자동 검증/갱신은 보조 항목이 아니라 핵심 항목이다.
- "AI가 grep/search로 알아내면 된다"는 상태는 낮은 점수다.
- 최종 점수는 evidence 기반으로만 부여한다.

```text
Total Score = A + B + C + D + E + F + G
```

## Grade Bands

| Score | Grade | Meaning |
| ---: | --- | --- |
| 90-100 | A | AI가 큰 기능도 비교적 독립적으로 안전하게 수행 가능 |
| 75-89 | B | 일반적인 feature/fix는 가능하지만 일부 맥락은 사람 확인 필요 |
| 60-74 | C | 작은 변경은 가능하지만 영향 범위 추적과 검증에서 자주 막힘 |
| 40-59 | D | AI가 코드를 읽는 시간보다 추측/질문 시간이 많아짐 |
| 0-39 | F | AI 협업을 위한 기본 navigation/context가 부족함 |

## A. AI Navigation & Coverage, 15점

AI가 "어디를 봐야 하는가"를 빠르게 찾을 수 있는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | AI가 repo를 직접 grep/search하며 구조를 추측해야 함 |
| 5 | 주요 module 일부에 README/context 존재 |
| 10 | 대부분의 핵심 module에 역할, entry point, related files 정리 |
| 15 | 모든 핵심 module/workflow에 AI navigation guide 존재. "어디를 봐야 하는가"를 1-2 hops 안에 찾을 수 있음 |

권장 측정식:

```text
Navigation Coverage = AI-context로 안내 가능한 핵심 module 수 / 전체 핵심 module 수
```

체크 포인트:

- repo root에 AGENTS/CLAUDE/README 같은 진입 문서가 있는가
- module별 owner, purpose, entry point, public API가 정리되어 있는가
- workflow별 문서가 code path와 연결되어 있는가
- "수정 전 반드시 읽을 파일"이 명확한가

## B. Context Document Quality, 20점

문서가 단순히 많은 것이 아니라, AI가 작업 결정을 내릴 수 있게 압축되어 있는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | 문서가 없거나 오래된 README 수준 |
| 5 | 설치/실행 방법은 있으나 설계 의도와 변경 규칙이 부족 |
| 10 | 주요 기능의 목적, 제약, 실행 방법, 테스트 방법이 정리됨 |
| 15 | 문서가 작업별로 분리되어 있고, 결정/금지/예외 케이스가 명확함 |
| 20 | context 문서가 "compass, not encyclopedia"처럼 작동함. AI가 필요한 판단 기준을 빠르게 찾고, 불필요한 장황함이 적음 |

좋은 문서의 기준:

- 현재 합의와 맞다.
- 코드 전체를 복붙 설명하지 않는다.
- "왜 이렇게 했는지"와 "무엇을 하면 안 되는지"를 포함한다.
- task type별로 먼저 읽을 문서가 다르다.
- 예외와 운영 제약을 숨기지 않는다.

감점 예시:

- README는 긴데 실제 변경 시 필요한 설계 결정이 없다.
- 여러 문서가 서로 다른 결론을 말한다.
- 문서가 코드 구조를 나열하지만 workflow를 설명하지 않는다.
- 최신 코드를 반영하지 않는 stale 문서가 핵심 진입점에 있다.

## C. Tribal Knowledge Externalization, 20점

팀원 머릿속에만 있는 규칙이 문서/테스트/체크리스트로 밖에 나와 있는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | 주요 규칙이 사람에게 물어봐야만 알 수 있음 |
| 5 | 일부 암묵지가 이슈/채팅/주석에 흩어져 있음 |
| 10 | 핵심 운영 규칙과 흔한 실패 케이스가 문서화됨 |
| 15 | 결정 기록, 금지 패턴, migration/release 주의점이 구조화됨 |
| 20 | AI가 review checklist, decision log, failure playbook만 보고도 대부분의 hidden rule을 파악 가능 |

체크 포인트:

- decision log가 있는가
- "하지 않기로 한 것"이 기록되어 있는가
- 장애/실패/rollback 경험이 문서화되어 있는가
- reviewer가 반복해서 지적하는 항목이 체크리스트화되어 있는가
- 도메인 용어와 business rule이 코드명만으로 추측되지 않게 정리되어 있는가

감점 예시:

- "그건 원래 그렇게 하면 안 됨" 같은 규칙이 문서에 없다.
- 실패 사례가 PR 댓글이나 개인 기억에만 남아 있다.
- 설정값의 이유와 운영 범위가 없다.
- test가 없는데 manual QA 기준도 없다.

## D. Cross-Module Dependency & Data Flow Mapping, 15점

한 변경이 어떤 module, API, DB, job, UI에 영향을 주는지 AI가 추적할 수 있는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | 의존성과 data flow를 코드에서 역추적해야 함 |
| 5 | 일부 architecture diagram 또는 module 설명 존재 |
| 10 | 핵심 API/data flow/job flow가 문서화되어 있음 |
| 15 | 변경 유형별 영향 범위가 mapping되어 있고, AI가 관련 파일/테스트/운영 영향까지 따라갈 수 있음 |

체크 포인트:

- API contract와 client usage가 연결되어 있는가
- DB table/read model/job/event 흐름이 문서화되어 있는가
- frontend-backend-contract가 별도로 명시되어 있는가
- 모듈 간 boundary와 ownership이 명확한가
- diagram이 실제 코드/문서와 함께 갱신되는가

권장 산출물:

- system diagram
- API spec
- data model
- job/scheduler plan
- frontend integration plan
- change-impact checklist

## E. Verification & Quality Gates, 15점

AI가 만든 변경이 실제로 안전한지 검증할 수 있는 자동/수동 gate가 있는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | 검증 기준 없음. "눈으로 확인"에 의존 |
| 5 | 기본 build/test 명령은 있으나 coverage와 failure case가 부족 |
| 10 | unit/integration/e2e 또는 QA scenario가 주요 path를 커버 |
| 15 | AI 변경용 검증 루틴이 명확함. test, lint, typecheck, migration check, manual QA가 작업 유형별로 연결됨 |

체크 포인트:

- 로컬에서 재현 가능한 test command가 있는가
- CI가 PR마다 핵심 검증을 수행하는가
- API success/failure scenario가 있는가
- migration/schema 변경 검증 기준이 있는가
- flaky test, external dependency, env var 처리 기준이 있는가
- AI가 final answer에 어떤 검증을 했는지 남길 수 있는가

감점 예시:

- 테스트는 있지만 실행 방법이 불명확하다.
- 외부 API/mock 전략이 없다.
- QA 문서가 happy path만 다룬다.
- 실패 시 어떤 로그를 봐야 하는지 없다.

## F. Freshness & Self-Maintenance, 10점

문서와 context가 코드 변경 후 stale해지지 않도록 유지되는지 평가한다.

| Score | Criteria |
| ---: | --- |
| 0 | 문서 최신성 관리 없음 |
| 3 | 사람이 가끔 수동으로 업데이트 |
| 6 | PR checklist나 reviewer rule로 문서 갱신을 요구 |
| 8 | 일부 문서/diagram/API spec이 자동 생성 또는 검증됨 |
| 10 | context freshness가 CI/checklist/ownership으로 관리되고 stale 가능성이 낮음 |

체크 포인트:

- 문서 owner가 있는가
- 문서 변경 조건이 PR template/checklist에 있는가
- API spec, schema, diagram이 코드와 drift detection 되는가
- 오래된 문서를 발견하는 주기적 리뷰가 있는가
- agent log나 decision log가 실제로 이어지고 있는가

## G. Agent Performance Outcomes, 5점

AI-ready 개선이 실제 작업 효율로 이어지는지 측정하는 항목이다.

| Score | Criteria |
| ---: | --- |
| 0 | AI 작업 성과를 측정하지 않음 |
| 2 | 체감상 좋아졌다는 수준의 비정형 기록만 있음 |
| 3 | AI task별 blocked reason, review comments, rework를 일부 기록 |
| 5 | 성공률, cycle time, rework rate, escaped defect 같은 지표를 정기적으로 추적 |

권장 지표:

- AI task success rate
- first-pass review acceptance rate
- average context discovery time
- rework count per AI task
- escaped defect count after AI-assisted changes
- "질문 없이 완료 가능한 작업" 비율

## Evidence Template

평가자는 항목마다 evidence를 남긴다.

```json
{
  "category": "A. AI Navigation & Coverage",
  "score": 10,
  "maxScore": 15,
  "evidence": [
    "AGENTS.md defines task-specific read rules",
    "docs/backend/* covers backend workflows",
    "frontend workflow has integration plan"
  ],
  "gaps": [
    "No module-level navigation index for contracts/",
    "No generated dependency map"
  ],
  "recommendedActions": [
    {
      "title": "Add module index for contracts/",
      "impact": "medium",
      "effort": "low",
      "roi": "high"
    }
  ]
}
```

## ROI Action Priority

개선 액션은 점수만 보고 고르지 말고 ROI로 정렬한다.

| Priority | Rule |
| --- | --- |
| P0 | AI가 현재 작업을 안전하게 끝내지 못하게 막는 context gap |
| P1 | 자주 반복되는 질문/리뷰 지적을 줄이는 문서 또는 검증 |
| P2 | 변경 영향 범위 추적을 빠르게 만드는 mapping |
| P3 | 있으면 좋지만 즉시 작업 성공률에는 영향이 작은 정리 |

권장 ROI 계산:

```text
ROI = (Impact x Frequency x Risk Reduction) / Effort
```

## Final Report Shape

AI-ready audit 결과는 다음 형태를 권장한다.

```json
{
  "repo": "example/repo",
  "totalScore": 78,
  "grade": "B",
  "categories": [
    {
      "id": "A",
      "name": "AI Navigation & Coverage",
      "score": 12,
      "maxScore": 15,
      "summary": "Core workflows are documented, but module-level coverage is partial."
    }
  ],
  "topGaps": [
    "No stale-context detection in CI",
    "No explicit change-impact checklist for schema changes"
  ],
  "recommendedActions": [
    {
      "priority": "P0",
      "title": "Add schema migration review checklist",
      "owner": "backend",
      "effort": "low",
      "expectedScoreGain": 4
    }
  ]
}
```
