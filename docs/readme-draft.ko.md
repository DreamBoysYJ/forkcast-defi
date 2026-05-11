# Forkcast DeFi

**Aave V3 + Uniswap v4 기반 원버튼 레버리지 LP dApp과, 온체인 이벤트를 인덱싱하는 Spring Boot 백엔드 프로젝트입니다.**

Forkcast DeFi는 사용자가 지갑으로 직접 트랜잭션을 보내는 DeFi dApp입니다.
프론트엔드는 Aave / Uniswap / StrategyRouter 상태를 보여주고, 스마트 컨트랙트는 `supply → borrow → swap → LP → close` 전략 흐름을 실행합니다.

여기에 Spring Boot 백엔드를 추가해, 온체인에서 발생한 이벤트와 포지션 상태를 DB에 저장하고 조회 API로 제공합니다.

이 프로젝트의 핵심은 단순한 컨트랙트 데모가 아니라, **지갑 기반 온체인 실행 흐름과 백엔드 인덱싱/조회 시스템을 함께 설계한 end-to-end DeFi 포트폴리오**입니다.

![Forkcast DeFi profit source](image.png)

---

## 1. 프로젝트 개요

Forkcast DeFi는 Aave V3와 Uniswap v4를 이용해 레버리지 LP 포지션을 여는 데모 dApp입니다.

사용자는 한 번의 액션으로 `supply → borrow → swap → LP` 흐름을 실행하고, 포지션을 닫을 때는 그 반대 방향으로 LP 제거 → 스왑 → 부채 상환 → 담보 인출 순서로 정리합니다.

처음 버전은 컨트랙트와 프론트엔드 중심이었습니다. 하지만 dApp만으로는 다음 기능을 안정적으로 제공하기 어렵습니다.

- 과거 포지션 이벤트 / 풀 가격 이벤트 조회
- 전체 오픈 포지션과 포지션 lifecycle timeline 조회
- 주기적인 포지션 상태 스냅샷 저장
- pending transaction과 실제 온체인 이벤트의 reconciliation
- retry-safe event sync, scheduled job 실행 이력과 운영 상태 추적

그래서 v1 백엔드는 **off-chain indexer / query backend** 역할을 합니다.

### 책임 경계

- 백엔드는 사용자 대신 트랜잭션을 보내지 않습니다.
- 사용자 자산과 실행 권한은 항상 지갑과 컨트랙트에 남아 있습니다.
- 백엔드는 온체인에서 이미 일어난 일을 관찰해 read model과 snapshot으로 저장합니다.
- 최종 진실은 항상 온체인 이벤트입니다. 프론트가 보내는 tx hint는 best-effort 힌트일 뿐입니다.

---

## 2. Live Demo & 발표 영상

- Live dApp: <https://forkcast-web-799298411936.asia-northeast3.run.app/>
- YouTube (한국어 자막 O): <https://youtu.be/3bI2R2cJe6c?si=HLHtmrSIzuoiiXxS>

데모를 사용하려면 Sepolia ETH와 Aave Sepolia 테스트 토큰이 필요합니다.

- Aave Sepolia Faucet: <https://gho.aave.com/faucet/>
- Sepolia ETH Faucet: <https://sepolia-faucet.pk910.de/>

---

## 3. Monorepo 구조와 진입점

```text
.
├─ contracts/   # Aave V3 + Uniswap v4 전략 컨트랙트 (Foundry)
├─ backend/     # Spring Boot 온체인 이벤트 인덱서 / 조회 API
├─ web/         # Next.js dApp 프론트엔드
└─ docs/        # API, 백엔드 설계, 운영, QA 문서
```

관심 영역에 따라 다음 README로 이동하세요. 각 폴더 README에 도메인별 깊이가 들어 있습니다.

| 폴더 | 무엇이 들어 있는가 | 들어가서 보게 되는 것 |
|------|------------------|----------------------|
| **[`contracts/`](contracts/README.ko.draft.md)** | Aave V3 + Uniswap v4 전략 컨트랙트, per-user vault, 커스텀 hook | `StrategyRouter` · `UserAccount` · `MiniV4SwapRouter` · `SwapPriceLoggerHook` · `StrategyLens`, open / close / collectFees 시퀀스, 테스트 전략 |
| **[`backend/`](backend/README.ko.draft.md)** | Spring Boot 기반 off-chain indexer / query 백엔드 | 4계층 데이터 모델 (operational · raw · read model · snapshot), event-sync · snapshot 잡, `job_lock` + `sync_cursor` + OIDC scheduler, API 응답 형식 |
| **[`web/`](web/README.md)** | Next.js + wagmi/viem 기반 dApp UI | 지갑 트랜잭션 흐름, 백엔드 API 보강 통합, Uniswap v4 hook event UI |

추가 설계 / 운영 문서:

- API 응답 예시: [api-spec.md](api-spec.md)
- 백엔드 설계 결정 모음: [docs/backend/decisions.md](docs/backend/decisions.md)
- 데이터 모델 상세: [docs/backend/data-model.md](docs/backend/data-model.md)
- scheduler 운영 계획: [docs/backend/scheduler-plan.md](docs/backend/scheduler-plan.md)
- 운영 문서 모음: [docs/ops/README.md](docs/ops/README.md)
- QA 시나리오: [docs/qa/test-scenarios.md](docs/qa/test-scenarios.md)

---

## 4. 전체 아키텍처

![End-to-end system flow](image-system.png)

사용자는 프론트에서 지갑으로 컨트랙트를 호출합니다. 컨트랙트는 Aave / Uniswap v4와 상호작용하면서 Router / Hook 이벤트를 발생시킵니다.

백엔드는 Cloud Scheduler가 주기적으로 호출하는 `event-sync` 잡에서 체인 로그를 읽어 raw event와 read model을 갱신하고, `snapshot` 잡에서 `StrategyLens`를 호출해 현재 포지션 상태 사진을 저장합니다.

각 모듈 / 계층의 상세 설계는 위 3번 표의 sub-README에서 다룹니다.

---

## 5. 한계와 의도적 단순화

이 프로젝트는 실제 운용 가능한 DeFi 상품이 아니라, DeFi와 백엔드 시스템 설계를 학습하고 보여주기 위한 technical prototype입니다.

- Sepolia 테스트넷 기준, 커스텀 토큰과 데모 풀 사용
- 실제 시장 가격 / PnL과 다를 수 있음
- 백엔드 sync는 완전 실시간이 아님 — v1은 `latest − 5` safe-head 전략을 사용
- pagination / cursor API는 단순화되어 있음
- 복잡한 analytics, alerting, admin dashboard는 범위 밖

도메인별 한계와 future work는 각 폴더 README에서 다룹니다.

---

## 6. Thanks

Cyfrin과 t4sk의 DeFi / Uniswap v4 강의와 자료에서 많은 도움을 받았습니다.

- Cyfrin / UniswapV4 Contributor: <https://github.com/Cyfrin/defi-uniswap-v4>
