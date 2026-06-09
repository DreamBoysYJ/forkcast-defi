# 김영주 — 개발자 프로필 요약

> 이 문서의 목적: 이 레포는 **취업 준비용 사이드 프로젝트**다. 개선 사안을 논의하거나
> 채용 공고 요구조건에 맞춰 작업할 때, 매번 이력서/포트폴리오 PDF를 통째로 읽지 않고
> 이 요약본만 참조하면 되도록 정리한 것이다.
>
> 원본: `get_jobs/이력서-김영주 복사본.pdf` (3p), `get_jobs/포트폴리오-김영주 복사본.pdf` (9p)
> 최종 갱신: 2026-06-09

## 한 줄 정체성

블록체인 코어(클라이언트 직접 구현)부터 스마트 컨트랙트, Web3 백엔드/프론트 연동까지
직접 구현해온 개발자. "소통이 되는 블록체인 개발자"를 셀링 포인트로 잡고 있음
(임원 대상 기술 발표, 5년간 300+ 기술 글 작성, 강의 제작 경험).

## 핵심 스펙

- **경력 연차:** 정규직 1.1년(티맥스 메타에이아이, 23.09–24.10) + 강의/프리랜서/개인 프로젝트
- **학력:** 경희대 경영학과 (4.11/4.5, 19.03–23.02) — 비전공 → 부트캠프/직무교육으로 전환
- **자격/어학:** SQLD (25.06), TOEIC 960 (23.06)
- **수상:** 체인링크 글로벌 해커톤 Top-Quality Prizes 2회(23.06, 24.06), 아주대 LINC 3.0 사업단장상 1위(22.08)
- **CS 기반:** 운영체제·네트워크·컴퓨터구조·분산시스템 대학 공개강의 학습 (비전공 보완)

## 경력 타임라인

| 기간 | 소속/형태 | 역할 |
|---|---|---|
| 23.09–24.10 | 티맥스 메타에이아이 (정규직) | 블록체인 엔지니어 — 계약 자동이행 플랫폼 POC/MVP 기획·프론트·컨트랙트, Geth Private Network 구축, Go 블록체인 클라이언트 프로토타입 |
| 25.06–25.09 | 클래스101 | 블록체인 이론/컨트랙트 강의 제작 (Bitcoin/Ethereum 구조, EVM, ERC) |
| 26.01–26.03 | 프리랜서 (3인팀 리드) | Polygon 스테이블코인 결제/송금 Android 앱 |

## 대표 프로젝트

1. **Forkcast DeFi** (개인, 25.10–25.11 / 26.04–26.05) — **이 레포**
   - Aave V3 + Uniswap v4 레버리지 LP dApp. supply→borrow→swap→LP→close 전략을 컨트랙트로 실행.
   - **컨트랙트:** StrategyRouter 중심 오케스트레이션, 사용자별 UserAccount vault(소유 경계 분리),
     Aave 리스크 파라미터 기반 borrow sizing, close 전 debt shortfall preview,
     Uniswap v4 전용 MiniV4SwapRouter, AFTER_SWAP 관찰용 Hook, StrategyLens read layer.
   - **백엔드(Spring Boot):** 트랜잭션을 대신 보내지 않는 **off-chain indexer/query backend**.
     `eth_getLogs`로 raw event 보존 → read model 변환, StrategyLens `eth_call` 스냅샷,
     safe-head 기반 sync 정책, Cloud Run 다중 인스턴스 대비 lease 기반 job lock,
     job 실행 이력 별도 트랜잭션 분리, snapshot job 부분 실패 처리.
   - **인프라:** GCP Cloud Run / Cloud SQL / Cloud Scheduler / Secret Manager, Google OIDC scheduler auth.
   - **스택:** Java 21, Spring Boot, Spring Data JPA, PostgreSQL, Flyway, web3j, Solidity, Foundry.

2. **블록체인 클라이언트 구현** (회사→개인, 24.07–25.01) — Go
   - Ethereum 내부 구조 이해를 위해 Go로 직접 구현. UDP Node Discovery + TCP P2P 전파,
     JSON-RPC, ECDSA/nonce/balance 검증, mempool pending/future 분리 및 nonce gap 승격,
     round-robin 트랜잭션 선택, 블록 생성/검증/전파, LevelDB 상태 저장, miner reward.

3. **계약 자동 이행 플랫폼 POC/MVP** (회사, 24.02–24.08)
   - 기획+프론트(React/Ethers.js/MobX)+컨트랙트(Solidity/Foundry). 연봉/내기 계약서 자동이행,
     금전 계산 로직 Foundry 테스트 검증, 사수 코드리뷰.

4. **Ethereum Private Network 구축** (회사, 23.11–24.01)
   - Geth + k8s(Tmax Cloud). genesis.json ConfigMap 분리, PV/PVC 영구 스토리지,
     `-nat extip` enode advertise 트러블슈팅.

5. **스테이블코인 결제 앱** (프리랜서, 26.01–26.03) — React Native
   - WalletConnect 비수탁 지갑, 백엔드 없이 온체인 직접 조회. Zustand store 분리 +
     isFetching/lastFetchedAt로 **RPC 호출량 약 75% 절감**, 낙관적 업데이트 + 제한 폴링,
     모바일 지갑 연동 실패 케이스 처리.

6. **Real Maritime Assets** (해커톤 팀장, 24.04–24.06) — 체인링크 수상
   - 선박 RWA. ETH 담보 스테이블코인(Chainlink Data Feeds/Automation), 청산가 가중평균 재계산,
     ERC-6960 Dual Layer Token, 거버넌스 토큰 연동.

## 기술 스택 (자기신고 기준)

- **언어:** Java, Solidity, TypeScript, JavaScript, Golang, Python
- **백엔드:** Spring Boot, Spring Data JPA, Node.js, Prisma
- **DB/마이그레이션:** PostgreSQL, JDBC, Flyway, MongoDB, SQLite, LevelDB
- **블록체인/Web3:** Foundry, wagmi, viem, Ethers.js, Web3.js, web3j, Geth, Anchor, Cosmos SDK, CosmWasm, Chainlink
- **DeFi:** Uniswap v2–v4, Aave V3
- **인프라:** GCP(Cloud Run, Cloud SQL, Cloud Scheduler, Secret Manager, GKE), k8s(Tmax-Cloud)
- **프론트:** React, Next.js, Zustand, MobX, Tailwind, SCSS, React Native
- **오픈소스 PR:** Cyfrin(Uniswap v4 교육자료, 25.12), Ludium(Cosmos SDK 교육자료, 25.08)

## 강점 / 포지셔닝

- 블록체인 **코어 동작 원리를 직접 구현 수준으로 이해** (클라이언트, Private Network, EVM 내부).
- 컨트랙트 ↔ 백엔드 ↔ 프론트 **풀스택 Web3 연동** 경험.
- 설계 의사결정의 **트레이드오프를 명확히 설명**하는 문서화 습관 (포트폴리오가 기능나열이 아닌 "왜")
- 비전공 → CS 기초를 별도 학습으로 보완 중.

## 채용 매칭 시 약점/공백 (개선 후보)

> 채용 공고 요구조건 통계와 대조해 보강 우선순위를 정할 때 참고.

- **백엔드 깊이:** Spring Boot 실무 경험이 개인 프로젝트(Forkcast) 중심. 정규직 백엔드 경력은 짧음.
- 일반 백엔드 채용에서 흔히 요구되는 항목 중 이력서에 약하거나 없는 것:
  Redis/캐시, 메시지 큐(Kafka/RabbitMQ), 대규모 트래픽/성능, MSA, 테스트 커버리지 지표,
  CI/CD 파이프라인 상세, 모니터링/관측성(Prometheus/Grafana), Docker/k8s 운영 깊이.
- 도메인이 **블록체인/Web3에 집중** → 일반 백엔드 공고와 일반 SI/서비스 공고는 매칭 폭이 다름.
