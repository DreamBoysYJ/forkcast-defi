# Cloud Scheduler Setup

> v1 Cloud Scheduler 구성 문서.
> Cloud Run이 scale-to-zero 가능하므로 Spring @Scheduled 대신 Cloud Scheduler를 사용한다.
> 자세한 설계 근거는 `docs/backend/decisions.md` §11, `docs/backend/scheduler-plan.md` §2 참조.

---

## 전제 조건

- 백엔드 Cloud Run 서비스 URL 확정 완료 (`docs/ops/cloud-run-config.md` §1-5)
- `SCHEDULER_AUTH_AUDIENCE` env가 백엔드 URL로 설정 완료
- scheduler 전용 서비스 계정 생성 완료 (아래 §1)

```bash
export PROJECT_ID=<YOUR_GCP_PROJECT_ID>
export REGION=asia-northeast3
export BACKEND_URL=$(gcloud run services describe forkcast-backend \
  --region $REGION \
  --format 'value(status.url)')
export SCHEDULER_SA=forkcast-scheduler@$PROJECT_ID.iam.gserviceaccount.com
```

---

## 1. Scheduler 전용 서비스 계정 생성

```bash
# 서비스 계정 생성
gcloud iam service-accounts create forkcast-scheduler \
  --display-name "Forkcast Cloud Scheduler"

# Cloud Run Invoker 권한 부여
gcloud run services add-iam-policy-binding forkcast-backend \
  --region $REGION \
  --member "serviceAccount:$SCHEDULER_SA" \
  --role "roles/run.invoker"
```

이 서비스 계정이 Cloud Scheduler HTTP 호출 시 OIDC 토큰을 발행하는 주체가 된다.
백엔드는 이 토큰을 검증해 내부 job endpoint 호출을 허용한다.

---

## 2. Job 목록

| Job | 엔드포인트 | 스케줄 | 타임존 |
|-----|-----------|--------|--------|
| `forkcast-event-sync` | `POST /internal/jobs/event-sync` | `*/5 * * * *` (5분마다) | `Asia/Seoul` |
| `forkcast-snapshot` | `POST /internal/jobs/snapshot` | `*/5 * * * *` (5분마다) | `Asia/Seoul` |

---

## 3. gcloud 명령

### 3-1. event-sync job 생성

```bash
gcloud scheduler jobs create http forkcast-event-sync \
  --location $REGION \
  --schedule "*/5 * * * *" \
  --time-zone "Asia/Seoul" \
  --uri "$BACKEND_URL/internal/jobs/event-sync" \
  --http-method POST \
  --oidc-service-account-email $SCHEDULER_SA \
  --oidc-token-audience $BACKEND_URL \
  --attempt-deadline 540s \
  --description "Forkcast event-sync: chain log ingest & read model update"
```

### 3-2. snapshot job 생성

```bash
gcloud scheduler jobs create http forkcast-snapshot \
  --location $REGION \
  --schedule "*/5 * * * *" \
  --time-zone "Asia/Seoul" \
  --uri "$BACKEND_URL/internal/jobs/snapshot" \
  --http-method POST \
  --oidc-service-account-email $SCHEDULER_SA \
  --oidc-token-audience $BACKEND_URL \
  --attempt-deadline 540s \
  --description "Forkcast snapshot: open position state collection"
```

> `--oidc-token-audience`는 백엔드의 `SCHEDULER_AUTH_AUDIENCE` env 값과 반드시 일치해야 한다.

---

## 4. 수동 트리거 (테스트용)

```bash
# event-sync 수동 실행
gcloud scheduler jobs run forkcast-event-sync --location $REGION

# snapshot 수동 실행
gcloud scheduler jobs run forkcast-snapshot --location $REGION
```

수동 트리거도 동일한 OIDC 토큰을 사용하므로 인증 흐름 전체를 검증할 수 있다.

---

## 5. Job 일시 정지 & 재개

```bash
# 일시 정지 (비용 절약, 디버깅 시)
gcloud scheduler jobs pause forkcast-event-sync --location $REGION
gcloud scheduler jobs pause forkcast-snapshot --location $REGION

# 재개
gcloud scheduler jobs resume forkcast-event-sync --location $REGION
gcloud scheduler jobs resume forkcast-snapshot --location $REGION
```

---

## 6. 스케줄 변경

운영 중 간격을 변경해야 할 경우:

```bash
# event-sync를 10분 간격으로 변경
gcloud scheduler jobs update http forkcast-event-sync \
  --location $REGION \
  --schedule "*/10 * * * *"
```

변경 기준:
- sync lag이 허용 범위 안이면 간격을 늘려 RPC/DB 비용 절감
- 포지션 수 증가로 snapshot이 2분 이상 걸리면 간격을 늘림
- job_lock 2분 lease가 부족하면 lease 시간도 함께 조정 (코드 변경 필요)

---

## 7. 실행 로그 확인

```bash
# Cloud Scheduler 실행 이력 (최근 5회)
gcloud scheduler jobs describe forkcast-event-sync --location $REGION

# Cloud Run 로그에서 job 실행 결과 확인
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=forkcast-backend AND textPayload:\"event-sync\"" \
  --limit 20 \
  --format "value(timestamp, textPayload)"
```

DB에서 직접 확인:
```sql
-- 최근 job 실행 기록
SELECT job_name, status, started_at, finished_at, error_message
FROM job_run
ORDER BY started_at DESC
LIMIT 20;

-- sync cursor 현재 위치
SELECT * FROM sync_cursor;

-- job_lock 현재 상태
SELECT * FROM job_lock;
```

---

## 8. 인증 흐름 요약

```
Cloud Scheduler
  └─ HTTP POST /internal/jobs/event-sync
     Authorization: Bearer <Google OIDC ID Token>
       ├─ iss: accounts.google.com
       ├─ email: forkcast-scheduler@PROJECT.iam.gserviceaccount.com
       └─ aud: https://forkcast-backend-<hash>-an.a.run.app

백엔드 인터셉터 검증
  1. Google 공개키로 서명 검증
  2. audience == SCHEDULER_AUTH_AUDIENCE
  3. email == SCHEDULER_AUTH_ALLOWED_SERVICE_ACCOUNT
  └─ 실패 시 401/403 반환
```

로컬 개발에서는 `SCHEDULER_AUTH_ENABLED=false`로 설정하면 인증을 건너뛴다.
