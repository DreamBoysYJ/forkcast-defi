# Ops 문서 목록

Forkcast DeFi v1 운영 구성 문서.

## 문서

| 문서 | 내용 |
|------|------|
| [cloud-run-config.md](cloud-run-config.md) | 백엔드/프론트 Cloud Run 서비스 구성, env 변수, 배포 명령, 트래픽 전환/롤백, smoke test |
| [cloud-scheduler-setup.md](cloud-scheduler-setup.md) | Cloud Scheduler job 생성, 서비스 계정 권한, 수동 트리거, 스케줄 변경, 로그 확인 |
| [db-operations.md](db-operations.md) | Cloud SQL 인스턴스/DB/유저 생성, Secret Manager, Cloud Run 연결 방식, Flyway 절차, 일상 운영 쿼리 |

## 관련 문서

- `web/infra/cloud-run/README.md` — 프론트 서비스 덮어쓰기 배포 상세 절차
- `docs/backend/decisions.md` §11~13 — Cloud Scheduler 선택 근거, job lock, event-sync 블록 범위 정책
- `docs/backend/scheduler-plan.md` — job 책임, locking 전략, cursor 전략 상세

## 전체 배포 순서 요약

```
1. Secret Manager에 forkcast-db-password, forkcast-rpc-url 등록
2. Cloud SQL 인스턴스/DB/유저 생성
3. 백엔드 빌드 & forkcast-backend Cloud Run 배포 (PLACEHOLDER audience/cors)
4. 백엔드 URL 확정 → audience, cors env 업데이트
5. 프론트 빌드 & forcast-web 재배포 (NEXT_PUBLIC_BACKEND_URL 설정)
6. Cloud Scheduler job 2개 생성 (event-sync, snapshot)
7. Smoke test: 헬스체크, 포지션 API, 내부 endpoint 401, 수동 job 트리거
```
