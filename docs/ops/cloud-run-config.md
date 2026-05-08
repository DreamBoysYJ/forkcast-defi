# Cloud Run Config

> v1 운영 기준 Cloud Run 서비스 구성 문서.
> 백엔드는 신규 서비스, 프론트는 기존 `forcast-web` 서비스 재배포.

---

## 공통 변수

```bash
# 이 파일의 모든 gcloud 명령에서 공통으로 사용
export PROJECT_ID=<YOUR_GCP_PROJECT_ID>
export REGION=asia-northeast3          # 변경 시 아래 명령도 함께 수정
```

---

## 1. 백엔드 서비스 (`forkcast-backend`)

### 1-1. 개요

| 항목 | 값 |
|------|----|
| 서비스명 | `forkcast-backend` |
| 이미지 | `gcr.io/$PROJECT_ID/forkcast-backend:latest` |
| 포트 | `8080` |
| Cloud SQL 연결 | `/cloudsql/$PROJECT_ID:$REGION:forkcast-defi-db` |
| 최소 인스턴스 | `0` (scale-to-zero) |
| 최대 인스턴스 | `3` |
| 메모리 | `512Mi` |
| CPU | `1` |
| 인증 | 공개 (`--allow-unauthenticated`) — 내부 job endpoint는 앱 레이어에서 보호 |

### 1-2. Secret Manager에 보관할 값

아래 값은 평문으로 env에 넣지 않는다.
Cloud Run의 `--set-secrets` 옵션으로 마운트한다.

| Secret 이름 | 용도 |
|-------------|------|
| `forkcast-db-password` | DB 앱 유저 비밀번호 |
| `forkcast-rpc-url` | Sepolia RPC endpoint (Infura / Alchemy key 포함) |

나머지 비민감 값은 `--set-env-vars`로 직접 설정한다.

### 1-3. 환경 변수 전체 목록

| 변수명 | 예시 값 | 비고 |
|--------|---------|------|
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql:///forkcast_defi?cloudSqlInstance=$PROJECT_ID:$REGION:forkcast-defi-db&socketFactory=com.google.cloud.sql.postgres.SocketFactory` | Cloud SQL Unix socket 방식 |
| `SPRING_DATASOURCE_USERNAME` | `forkcast_app` | |
| `SPRING_DATASOURCE_PASSWORD` | Secret 마운트 → `forkcast-db-password` | |
| `RPC_URL` | Secret 마운트 → `forkcast-rpc-url` | |
| `STRATEGY_ROUTER_ADDRESS` | `0x8976fd44F134a93474c7809ff36De95FCbCc777a` | Sepolia |
| `HOOK_ADDRESS` | `0xf600DB53A6F76e3C8087524f48F35e46Ed7c8040` | Sepolia |
| `STRATEGY_LENS_ADDRESS` | `0xddc5349e0a354fe73edac0bdb15fba758be6f781` | Sepolia |
| `SCHEDULER_AUTH_ENABLED` | `true` | 운영에서는 반드시 `true` |
| `SCHEDULER_AUTH_ALLOWED_SERVICE_ACCOUNT` | `forkcast-scheduler@$PROJECT_ID.iam.gserviceaccount.com` | |
| `SCHEDULER_AUTH_AUDIENCE` | `https://forkcast-backend-<hash>-an.a.run.app` | 배포 후 확정 URL로 교체 |
| `APP_CORS_ALLOWED_ORIGINS` | `https://forcast-web-<hash>-an.a.run.app` | 프론트 URL 확정 후 교체 |
| `SYNC_BOOTSTRAP_WINDOW_BLOCKS` | `25` | 첫 배포 기본값, 필요 시 50~100으로 조정 |

> `SCHEDULER_AUTH_AUDIENCE`와 `APP_CORS_ALLOWED_ORIGINS`는 **백엔드 선배포 → URL 확정 → 재배포** 순서로 확정한다. 아래 §4 배포 순서 참조.

### 1-4. 빌드 & 배포 명령

```bash
# 1) JAR 빌드
cd backend
./gradlew bootJar

# 2) 컨테이너 이미지 빌드 & 푸시
gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/forkcast-backend:latest \
  .

# 3) Cloud Run 배포 (최초 또는 업데이트)
gcloud run deploy forkcast-backend \
  --image gcr.io/$PROJECT_ID/forkcast-backend:latest \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --cpu 1 \
  --min-instances 0 \
  --max-instances 3 \
  --add-cloudsql-instances $PROJECT_ID:$REGION:forkcast-defi-db \
  --set-env-vars "\
SPRING_DATASOURCE_URL=jdbc:postgresql:///forkcast_defi?cloudSqlInstance=$PROJECT_ID:$REGION:forkcast-defi-db&socketFactory=com.google.cloud.sql.postgres.SocketFactory,\
SPRING_DATASOURCE_USERNAME=forkcast_app,\
STRATEGY_ROUTER_ADDRESS=0x8976fd44F134a93474c7809ff36De95FCbCc777a,\
HOOK_ADDRESS=0xf600DB53A6F76e3C8087524f48F35e46Ed7c8040,\
STRATEGY_LENS_ADDRESS=0xddc5349e0a354fe73edac0bdb15fba758be6f781,\
SCHEDULER_AUTH_ENABLED=true,\
SCHEDULER_AUTH_ALLOWED_SERVICE_ACCOUNT=forkcast-scheduler@$PROJECT_ID.iam.gserviceaccount.com,\
SCHEDULER_AUTH_AUDIENCE=PLACEHOLDER_UPDATE_AFTER_DEPLOY,\
APP_CORS_ALLOWED_ORIGINS=PLACEHOLDER_UPDATE_AFTER_DEPLOY,\
SYNC_BOOTSTRAP_WINDOW_BLOCKS=25" \
  --set-secrets "\
SPRING_DATASOURCE_PASSWORD=forkcast-db-password:latest,\
RPC_URL=forkcast-rpc-url:latest"
```

### 1-5. 배포 후 URL 확정 & env 재설정

```bash
# 배포 후 URL 확인
BACKEND_URL=$(gcloud run services describe forkcast-backend \
  --region $REGION \
  --format 'value(status.url)')
echo $BACKEND_URL

# SCHEDULER_AUTH_AUDIENCE, APP_CORS_ALLOWED_ORIGINS 업데이트
# (프론트 URL도 확정된 뒤 설정)
FRONTEND_URL=$(gcloud run services describe forcast-web \
  --region $REGION \
  --format 'value(status.url)')

gcloud run services update forkcast-backend \
  --region $REGION \
  --update-env-vars "\
SCHEDULER_AUTH_AUDIENCE=$BACKEND_URL,\
APP_CORS_ALLOWED_ORIGINS=$FRONTEND_URL"
```

---

## 2. 프론트 서비스 기존 재배포 (`forcast-web`)

> 프론트는 **새 서비스를 만들지 않는다**.
> 기존 `forcast-web` 서비스에 새 revision을 올리는 방식으로 재배포한다.
> 자세한 절차는 `web/infra/cloud-run/README.md` 참조.

### 2-1. 개요

| 항목 | 값 |
|------|----|
| 서비스명 | `forcast-web` (기존 유지) |
| 이미지 | `gcr.io/$PROJECT_ID/forcast-web:latest` |
| 포트 | `3000` |
| 인증 | 공개 (`--allow-unauthenticated`) |

### 2-2. 추가 env 변수 (백엔드 연동용)

`NEXT_PUBLIC_BACKEND_URL`은 **런타임 env가 아니라 빌드 타임 값**이다.  
Next.js는 `NEXT_PUBLIC_*` 변수를 `npm run build` 시점에 번들에 정적으로 박아넣는다.  
`gcloud run deploy --update-env-vars`로 나중에 설정해도 이미 빌드된 JS 번들에는 반영되지 않는다.  
따라서 반드시 **Docker 빌드 시 `--build-arg`로 주입**해야 한다.

| 변수명 | 주입 방식 | 값 |
|--------|----------|-----|
| `NEXT_PUBLIC_BACKEND_URL` | Docker build arg (`web/cloudbuild.yaml`의 `_NEXT_PUBLIC_BACKEND_URL`) | 백엔드 Cloud Run URL (§1-5에서 확정한 값) |
| `NEXT_PUBLIC_POOL_ID` | Docker build arg (`web/cloudbuild.yaml`의 `_NEXT_PUBLIC_POOL_ID`) | Uniswap v4 pool ID (bytes32) |

### 2-3. 재배포 명령

```bash
# 백엔드 URL 확정 후 실행
BACKEND_URL=$(gcloud run services describe forkcast-backend \
  --region $REGION \
  --format 'value(status.url)')

# 프론트 이미지 빌드 — NEXT_PUBLIC_* 변수를 build arg로 주입
# (--tag 단독 사용 금지: build arg를 전달할 수 없음)
POOL_ID=0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c
cd web
gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions _NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL,_NEXT_PUBLIC_POOL_ID=$POOL_ID \
  .

# 기존 forcast-web 서비스에 새 revision 배포
# NEXT_PUBLIC_BACKEND_URL은 빌드 시 번들에 이미 포함됐으므로 여기선 설정 불필요
gcloud run deploy forcast-web \
  --image gcr.io/$PROJECT_ID/forcast-web:latest \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --port 3000
```

> **주의**: 백엔드 URL이 바뀌면 프론트를 반드시 **재빌드 + 재배포**해야 한다.  
> `gcloud run services update --update-env-vars`만으로는 번들이 교체되지 않는다.

---

## 3. 트래픽 전환 & 롤백

### 3-1. 점진적 트래픽 전환

```bash
# 새 revision 이름 확인
gcloud run revisions list --service forcast-web --region $REGION

# 트래픽 분할 예시: 새 revision에 10%만 보내기
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-revisions NEW_REVISION=10,PREV_REVISION=90

# 문제 없으면 전체 전환
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-latest
```

### 3-2. 롤백 (이전 revision으로 100% 복구)

```bash
# revision 목록 확인
gcloud run revisions list --service forcast-web --region $REGION

# 이전 revision으로 100% 롤백
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-revisions PREV_REVISION=100
```

백엔드도 동일한 방식으로 롤백한다 (`forcast-web` → `forkcast-backend`).

---

## 4. 전체 배포 순서

```
1. Cloud SQL 인스턴스 & DB 준비     → docs/ops/db-operations.md
2. Secret Manager 값 등록           → docs/ops/db-operations.md §1
3. 백엔드 빌드 & 배포 (PLACEHOLDER) → §1-4
4. 백엔드 URL 확정                  → §1-5
5. 백엔드 env 업데이트 (audience, cors)
6. 프론트 빌드 & forcast-web 재배포 → §2-3
7. Cloud Scheduler 생성             → docs/ops/cloud-scheduler-setup.md
8. 배포 후 smoke test               → §5
```

---

## 5. 배포 후 smoke test

```bash
# 백엔드 헬스 체크
curl -s $BACKEND_URL/actuator/health | jq .

# 오픈 포지션 API 응답 확인
curl -s "$BACKEND_URL/api/users/0x0000000000000000000000000000000000000001/positions/open?limit=5"

# 내부 job endpoint — 외부에서 토큰 없이 호출 시 401이어야 함
curl -s -o /dev/null -w "%{http_code}" \
  -X POST $BACKEND_URL/internal/jobs/event-sync
# 기대값: 401

# 프론트 접근 확인
FRONTEND_URL=$(gcloud run services describe forcast-web \
  --region $REGION \
  --format 'value(status.url)')
curl -s -o /dev/null -w "%{http_code}" $FRONTEND_URL
# 기대값: 200

# Cloud SQL 연결 확인 (Cloud Run Job 또는 Cloud Shell)
gcloud sql connect forkcast-defi-db --user=forkcast_app --database=forkcast_defi
```
