# Cloud Run — 프론트 배포 가이드

## 서비스 정보

| 항목 | 값 |
|------|----|
| 서비스명 | `forcast-web` (기존 서비스 유지) |
| 플랫폼 | Cloud Run (managed) |
| 인증 | 공개 (`--allow-unauthenticated`) |
| Secrets | `HOUSE_PK`, `RPC_URL` (Secret Manager) |

> **중요**: 프론트는 새 서비스를 만들지 않는다. 기존 `forcast-web` 서비스에 새 revision을 올리는 방식으로 재배포한다.

---

## 사전 요구사항

- 백엔드 Cloud Run 서비스(`forkcast-backend`) 배포 완료
- 백엔드 URL 확정 완료

```bash
export PROJECT_ID=<YOUR_GCP_PROJECT_ID>
export REGION=asia-northeast3

# 백엔드 URL 가져오기
BACKEND_URL=$(gcloud run services describe forkcast-backend \
  --region $REGION \
  --format 'value(status.url)')
echo "Backend URL: $BACKEND_URL"
```

---

## 기존 서비스 덮어쓰기 배포 절차

> **핵심 주의사항**: `NEXT_PUBLIC_BACKEND_URL`은 런타임 env가 아니라 **빌드 타임 값**이다.  
> Next.js는 `NEXT_PUBLIC_*` 변수를 `npm run build` 시 JS 번들에 정적으로 삽입한다.  
> `--update-env-vars`로 Cloud Run에 설정해도 이미 빌드된 번들에는 반영되지 않는다.  
> **반드시 `cloudbuild.yaml`의 `_NEXT_PUBLIC_BACKEND_URL` substitution으로 빌드 시 주입해야 한다.**

### 1단계: 이미지 빌드 & 푸시 (build arg 포함)

```bash
cd web

# NEXT_PUBLIC_BACKEND_URL을 build arg로 주입
# (--tag 단독 사용 금지: build arg 전달 불가)
POOL_ID=0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c
gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions _NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL,_NEXT_PUBLIC_POOL_ID=$POOL_ID \
  .
```

### 2단계: forcast-web 서비스에 새 revision 배포

```bash
# NEXT_PUBLIC_BACKEND_URL은 빌드 시 번들에 이미 포함됐으므로 deploy 시 설정 불필요
gcloud run deploy forcast-web \
  --image gcr.io/$PROJECT_ID/forcast-web:latest \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --port 3000 \
  --set-secrets "HOUSE_PK=HOUSE_PK:latest,RPC_URL=RPC_URL:latest,DEMO_TRADER_PRIVATE_KEY=DEMO_TRADER_PRIVATE_KEY:latest"
```

배포가 완료되면 새 revision이 자동으로 100% 트래픽을 받는다.
기존 URL은 변경되지 않는다.

---

## 트래픽 전환 & 롤백

### 점진적 전환 (카나리)

```bash
# revision 목록 확인
gcloud run revisions list --service forcast-web --region $REGION

# 새 revision에 10%만 보내기
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-revisions NEW_REVISION=10,PREV_REVISION=90

# 문제 없으면 전체 전환
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-latest
```

### 롤백

```bash
# 이전 revision으로 100% 롤백
gcloud run services update-traffic forcast-web \
  --region $REGION \
  --to-revisions PREV_REVISION=100
```

---

## 알려진 실수 & 주의사항

### ⚠️ CORS — 백엔드에 프론트 URL 두 가지 모두 등록해야 한다

Cloud Run은 같은 서비스에 URL 형식이 두 가지 존재한다:
- `https://forcast-web-2hdyy43b3q-du.a.run.app` (hash 형식, `gcloud run services list` 출력)
- `https://forcast-web-799298411936.asia-northeast3.run.app` (project-number 형식, `gcloud run deploy` 출력)

유저가 접속하는 URL은 **project-number 형식**이다. 백엔드 `APP_CORS_ALLOWED_ORIGINS`에 두 가지 모두 등록하지 않으면 API 호출이 전부 CORS 403으로 막힌다.

현재 등록된 값:
```
APP_CORS_ALLOWED_ORIGINS=https://forcast-web-2hdyy43b3q-du.a.run.app,https://forcast-web-799298411936.asia-northeast3.run.app
```

백엔드 CORS 수정 시 반드시 `--update-env-vars` 사용할 것. **`--set-env-vars`는 기존 env var를 전부 덮어쓰므로 절대 사용 금지.**

```bash
# 올바른 방법 (기존 env var 보존)
gcloud run services update forkcast-backend \
  --region asia-northeast3 \
  --update-env-vars "^|^APP_CORS_ALLOWED_ORIGINS=<값>" \
  --project forkcast-defi-demo

# 절대 하지 말 것 — 기존 env var 전부 삭제됨
# gcloud run services update ... --set-env-vars "APP_CORS_ALLOWED_ORIGINS=<값>"
```

---

## 배포 후 smoke test

```bash
FRONTEND_URL=$(gcloud run services describe forcast-web \
  --region $REGION \
  --format 'value(status.url)')

# HTTP 200 확인
curl -s -o /dev/null -w "%{http_code}" $FRONTEND_URL
```

브라우저에서 직접 접속해 지갑 연결 및 포지션 조회 동작을 확인한다.

---

## 환경 변수

| 변수명 | 출처 | 비고 |
|--------|------|------|
| `NEXT_PUBLIC_BACKEND_URL` | Docker build arg (`cloudbuild.yaml` `_NEXT_PUBLIC_BACKEND_URL`) | **빌드 타임 주입** — runtime env 설정으로는 적용 안 됨 |
| `HOUSE_PK` | Secret Manager | 기존 운영 중인 Secret |
| `RPC_URL` | Secret Manager | 기존 운영 중인 Secret |
| `DEMO_TRADER_PRIVATE_KEY` | Secret Manager | demo trader 서버 서명용 private key — `demoTrader.ts`에서 서버 전용으로만 읽음 |
