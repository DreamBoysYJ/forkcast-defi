# DB Operations

> Cloud SQL(PostgreSQL) 기준 운영 절차 문서.
> 인스턴스 생성부터 Secret 등록, Flyway 마이그레이션, 일상 운영까지 포함.

---

## 리소스 목록

| 항목 | 값 |
|------|----|
| Cloud SQL 인스턴스명 | `forkcast-defi-db` |
| DB명 | `forkcast_defi` |
| 앱 유저 | `forkcast_app` |
| PostgreSQL 버전 | `POSTGRES_16` |
| 리전 | `asia-northeast3` |
| 티어 | `db-f1-micro` (v1 초기 — 필요 시 상향) |
| 연결 방식 | Cloud SQL Connector (Unix socket, `socketFactory`) |

---

## 1. Secret Manager 값 등록

배포 전에 아래 두 Secret을 먼저 등록한다.

```bash
export PROJECT_ID=<YOUR_GCP_PROJECT_ID>

# DB 앱 유저 비밀번호
echo -n "<DB_APP_USER_PASSWORD>" | \
  gcloud secrets create forkcast-db-password \
    --data-file=- \
    --replication-policy automatic

# Sepolia RPC URL (Infura/Alchemy key 포함)
echo -n "https://sepolia.infura.io/v3/<YOUR_KEY>" | \
  gcloud secrets create forkcast-rpc-url \
    --data-file=- \
    --replication-policy automatic
```

Cloud Run 서비스 계정에 Secret 읽기 권한 부여:

```bash
# Cloud Run의 기본 서비스 계정 확인
CR_SA=$(gcloud run services describe forkcast-backend \
  --region asia-northeast3 \
  --format 'value(spec.template.spec.serviceAccountName)')
# 기본값은 PROJECT_NUMBER-compute@developer.gserviceaccount.com

gcloud secrets add-iam-policy-binding forkcast-db-password \
  --member "serviceAccount:$CR_SA" \
  --role "roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding forkcast-rpc-url \
  --member "serviceAccount:$CR_SA" \
  --role "roles/secretmanager.secretAccessor"
```

---

## 2. Cloud SQL 인스턴스 생성

```bash
gcloud sql instances create forkcast-defi-db \
  --database-version POSTGRES_16 \
  --region asia-northeast3 \
  --tier db-f1-micro \
  --storage-auto-increase \
  --storage-size 10GB \
  --backup-start-time 03:00 \
  --maintenance-window-day SUN \
  --maintenance-window-hour 4
```

> `--backup-start-time 03:00` — 자동 백업 활성화. 운영 초기부터 켜둔다.

---

## 3. DB & 앱 유저 생성

```bash
# DB 생성
gcloud sql databases create forkcast_defi \
  --instance forkcast-defi-db

# 앱 유저 생성
gcloud sql users create forkcast_app \
  --instance forkcast-defi-db \
  --password <DB_APP_USER_PASSWORD>
```

`<DB_APP_USER_PASSWORD>`는 위 §1에서 Secret Manager에 등록한 값과 동일하게 사용한다.

---

## 4. Cloud Run → Cloud SQL 연결 방식

백엔드 Cloud Run 서비스는 **Cloud SQL Connector (Unix socket)** 방식으로 연결한다.
VPC나 공인 IP 없이 GCP 내부 경로로 안전하게 연결된다.

### 4-1. Cloud Run 서비스에 Cloud SQL 연결 추가

`gcloud run deploy` 시 아래 옵션을 포함한다:

```
--add-cloudsql-instances $PROJECT_ID:asia-northeast3:forkcast-defi-db
```

### 4-2. SPRING_DATASOURCE_URL 형식

```
jdbc:postgresql:///forkcast_defi?cloudSqlInstance=$PROJECT_ID:asia-northeast3:forkcast-defi-db&socketFactory=com.google.cloud.sql.postgres.SocketFactory
```

- 호스트 없이 `///` — Unix socket을 통한 연결
- `socketFactory` — Cloud SQL Connector가 자동으로 소켓 경로를 설정
- `cloud-sql-connector` 의존성은 `build.gradle`의 `runtimeOnly 'com.google.cloud.sql:postgres-socket-factory:1.23.1'`로 제공됨

### 4-3. Cloud Run 서비스 계정 권한

Cloud Run 서비스 계정에 Cloud SQL Client 권한이 있어야 한다:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member "serviceAccount:$CR_SA" \
  --role "roles/cloudsql.client"
```

---

## 5. Flyway 운영 절차

### 5-1. 자동 마이그레이션

백엔드 Spring Boot 기동 시 Flyway가 자동으로 마이그레이션을 실행한다.
`backend/src/main/resources/db/migration/` 아래 `V{N}__*.sql` 파일을 순서대로 적용한다.

기본 동작:
- `V1__init_schema.sql` — 최초 테이블 생성
- 이후 버전은 순서대로 누적 적용
- 이미 적용된 버전은 건너뜀 (`flyway_schema_history` 테이블로 추적)

### 5-2. 새 마이그레이션 파일 추가 규칙

```
V{N+1}__{설명}.sql
예: V2__add_sync_cursor_index.sql
```

- 버전 번호는 연속으로 증가
- 이미 배포된 파일은 수정하지 않는다 (flyway checksum 오류 발생)
- 변경이 필요하면 새 버전으로 추가

### 5-3. 마이그레이션 실패 시 복구

배포 후 마이그레이션 실패 로그 확인:

```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=forkcast-backend AND textPayload:\"FlywayException\"" \
  --limit 10
```

수동 복구가 필요한 경우 Cloud Shell에서 직접 접속:

```bash
gcloud sql connect forkcast-defi-db --user=forkcast_app --database=forkcast_defi

-- 마이그레이션 이력 확인
SELECT version, description, success, installed_on
FROM flyway_schema_history
ORDER BY installed_rank DESC;

-- 실패한 버전 삭제 (수동 복구 시)
DELETE FROM flyway_schema_history WHERE success = false;
```

이후 SQL을 수정하고 재배포하면 Flyway가 다시 시도한다.

### 5-4. 로컬 개발 마이그레이션

로컬에서는 Spring Boot 기동 시 자동 적용된다.
별도 Flyway CLI 없이 `./gradlew bootRun`으로 충분하다.

---

## 6. 일상 운영

### 6-1. Cloud Shell에서 직접 접속

```bash
gcloud sql connect forkcast-defi-db --user=forkcast_app --database=forkcast_defi
```

### 6-2. 주요 모니터링 쿼리

```sql
-- 최근 job 실행 현황
SELECT job_name, status, started_at, finished_at,
       EXTRACT(EPOCH FROM (finished_at - started_at)) AS duration_sec
FROM job_run
ORDER BY started_at DESC
LIMIT 20;

-- sync cursor 위치
SELECT * FROM sync_cursor;

-- job lock 상태
SELECT job_name, locked_until, locked_by, updated_at,
       locked_until < now() AS expired
FROM job_lock;

-- 오픈 포지션 수
SELECT COUNT(*) FROM strategy_position WHERE is_open = true;

-- 최근 raw event 수집 현황 (최근 1시간, 온체인 이벤트 시각 기준)
-- raw_chain_event에 created_at 컬럼 없음 → event_timestamp 사용
SELECT COUNT(*), MAX(block_number), MIN(block_number)
FROM raw_chain_event
WHERE event_timestamp > now() - interval '1 hour';

-- pending_tx 잔존 현황
SELECT status, COUNT(*)
FROM pending_tx
GROUP BY status;
```

### 6-3. 막힌 job_lock 해제

2분 lease가 만료되면 자동 해제되지만, 수동 해제가 필요한 경우:

```sql
-- event-sync lock 강제 해제
UPDATE job_lock
SET locked_until = now()
WHERE job_name = 'event-sync';

-- snapshot lock 강제 해제
UPDATE job_lock
SET locked_until = now()
WHERE job_name = 'snapshot';
```

### 6-4. DB 사이즈 확인

```bash
gcloud sql instances describe forkcast-defi-db \
  --format "value(settings.dataDiskSizeGb)"
```

```sql
-- 테이블별 row 수 및 사이즈 대략 확인
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

---

## 7. 백업 & 복구

### 7-1. 자동 백업 확인

```bash
gcloud sql backups list --instance forkcast-defi-db
```

### 7-2. 수동 백업

```bash
gcloud sql backups create --instance forkcast-defi-db
```

### 7-3. 백업으로 복구

```bash
# 백업 ID 확인
gcloud sql backups list --instance forkcast-defi-db

# 복구
gcloud sql backups restore <BACKUP_ID> \
  --restore-instance forkcast-defi-db
```

> 복구는 인스턴스 전체를 덮어쓴다. 운영 중 복구 전에 반드시 확인.

---

## 8. 인스턴스 일시 정지 (비용 절감)

개발/테스트 기간에 인스턴스를 정지해 비용을 줄일 수 있다.

```bash
# 정지
gcloud sql instances patch forkcast-defi-db --activation-policy NEVER

# 재시작
gcloud sql instances patch forkcast-defi-db --activation-policy ALWAYS
```

> `db-f1-micro`는 정지 시 스토리지 비용만 청구됨.
