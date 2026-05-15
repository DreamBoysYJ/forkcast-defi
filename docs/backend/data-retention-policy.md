# Data Retention Policy

> 무기한 누적되는 테이블에 대한 보존 정책 설계 문서.
> 현재 코드베이스에 삭제 로직이 전혀 없는 상태이며, 이 문서는 어떤 데이터를 얼마나 보관할지 정의한다.

---

## 배경

5분마다 실행되는 두 job이 다음 테이블에 무기한으로 데이터를 쌓는다.

| 테이블 | 쌓이는 속도 | 삭제 로직 | 현재 row 수 (2026-05-15 기준) |
|--------|------------|----------|-------------------------------|
| `job_run` | 2건/5분 → 576건/일 | 없음 | 4,060건 |
| `position_snapshot` | (오픈 포지션 수)/5분 | 없음 | 2,079건 |

현재 row 수 자체가 용량 문제를 일으키지는 않지만, 장기 운영 시 무한 누적은 설계 결함이다.

---

## 1. job_run

### 용도

job 실행 이력 로그. 운영 중 다음 목적으로 사용된다:

- job 실패 여부 확인
- 실행 시간 및 처리 블록 범위 추적
- 디버깅 시 최근 실행 히스토리 조회

### 보존 정책 결정

| 질문 | 답 |
|------|-----|
| 얼마나 과거까지 봐야 하는가? | 디버깅 목적이면 최근 7~30일이면 충분 |
| 오래된 job_run이 비즈니스 로직에 영향을 주는가? | 없음. 조회용 로그 테이블 |
| 특정 실패 케이스를 장기 보관해야 하는가? | 검토 필요 (아래 참고) |

**확정 보존 기간: 14일**

14일치면 하루 576건 × 14일 = 8,064건 상한. 샘플 프로젝트 특성상 면접관이 주 사용자이므로 최소한으로 유지한다.

### 구현 옵션

**Option A: Flyway migration으로 주기적 DELETE (추천)**

별도 스케줄러 없이, Cloud Scheduler에 job을 하나 추가하거나 기존 event-sync job 실행 시 함께 처리한다.

```sql
DELETE FROM job_run
WHERE started_at < NOW() - INTERVAL '30 days';
```

**Option B: PostgreSQL 파티셔닝**

`started_at` 기준으로 월별 파티션을 나눠 오래된 파티션을 DROP. 현재 트래픽 규모에서는 과함.

**Option C: 외부 cron으로 직접 SQL 실행**

Cloud Scheduler에서 직접 SQL을 실행하는 방법은 없으므로, 별도 Cloud Run Job을 만들거나 기존 내부 endpoint를 활용해야 한다.

### 결정 사항

- [x] 보존 기간: **14일** 확정
- [x] 삭제 시점: `EventSyncService` 성공 실행 말미에 함께 처리
- [x] FAILED 상태 구분 없이 일괄 14일 적용

---

## 2. position_snapshot

### 용도

오픈 포지션의 온체인 상태를 주기적으로 기록한 시계열 데이터. 다음 목적으로 사용된다:

- 프론트엔드 포지션 상태 히스토리 표시
- Health factor, 자산 규모 등 시간에 따른 변화 추적

### 현재 쌓이는 방식

```
snapshot job 실행 (5분마다)
  → findByIsOpenTrue() — 현재 오픈 포지션 전체 조회
  → 포지션마다 온체인 상태 조회 (RPC 호출)
  → position_snapshot에 INSERT
```

포지션 1개 기준으로 하루 288건, 한 달 8,640건, 1년 105,120건.

### 보존 정책 결정

snapshot은 job_run과 달리 **비즈니스 데이터**다. 얼마나 오래 보관할지는 프론트에서 어디까지 보여줄지에 달려 있다.

| 질문 | 답 |
|------|-----|
| 프론트에서 몇 일치 히스토리를 표시하는가? | 미정 (결정 필요) |
| 포지션이 닫힌 이후에도 snapshot을 보관해야 하는가? | 결정 필요 |
| 5분 해상도가 꼭 필요한가, 아니면 더 낮춰도 되는가? | 결정 필요 |

**보존 기간 선택지**

| 기간 | 포지션 1개당 row 수 | 적합한 경우 |
|------|-------------------|------------|
| 7일 | 2,016건 | 단기 모니터링만 필요할 때 |
| 30일 | 8,640건 | 한 달 히스토리 제공 시 |
| 90일 | 25,920건 | 장기 추이 분석 시 |

**확정 보존 기간: 7일**

### 추가 고려: 포지션 종료 후 처리

포지션이 `is_open = false`가 되면 이후 snapshot은 더 이상 찍히지 않는다. 닫힌 포지션의 기존 snapshot을 계속 보관할 필요가 있는지도 결정해야 한다.

```sql
-- 닫힌 포지션의 snapshot 중 90일 이상 된 것 삭제
DELETE FROM position_snapshot
WHERE is_open = false
  AND snapshot_at < NOW() - INTERVAL '90 days';

-- 오픈 포지션도 90일 초과분 삭제
DELETE FROM position_snapshot
WHERE snapshot_at < NOW() - INTERVAL '90 days';
```

### 결정 사항

- [x] 보존 기간: **7일** 확정
- [x] 포지션 종료 여부 구분 없이 일괄 7일 적용
- [x] 삭제 시점: `SnapshotService` 성공 실행 말미에 함께 처리

---

## 3. 구현 방향 (확정 후 진행)

위 미결 사항들이 확정되면 다음 순서로 구현한다.

```
1. Flyway migration: 삭제 전용 SQL 작성
2. 기존 EventSyncService 또는 SnapshotService에 retention 실행 추가
   (별도 job보다 기존 job 실행 말미에 함께 처리하는 게 단순함)
3. 운영 배포 전 로컬에서 DELETE 쿼리 dry-run (COUNT로 확인)
4. 배포 후 pg_stat_user_tables로 row 수 감소 확인
```

---

## 관련 문서

- `docs/backend/data-model.md` — 테이블 스키마 전체
- `docs/backend/scheduler-plan.md` — job 구조 및 locking 전략
- `docs/ops/db-operations.md` — 운영 쿼리 및 모니터링
