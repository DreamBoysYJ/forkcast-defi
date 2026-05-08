# job_lock R1 수정 메모

> 날짜: 2026-05-08
> 범위: `job_lock` release blocker (`R1`) 문제 설명과 수정 요약

---

## 1. 어떤 문제가 있었나

`event-sync`와 `snapshot`은 둘 다 중복 실행을 막기 위해 `job_lock`에 의존한다.

기존 코드는 대략 이런 흐름이었다.

1. job 시작
2. `jobLockService.tryAcquire(...)` 호출
3. 오래 걸릴 수 있는 RPC 작업 시작
4. 전체 트랜잭션이 맨 마지막에 커밋

이 구조에서는 long-running work가 시작되기 전에 lock row가 DB에 확정 저장되지 않을 수 있었다.

그 결과, 거의 비슷한 시점에 들어온 다른 요청이 아직 예전 lock 상태를 보고 같은 job을 다시 시작할 여지가 있었다.

즉, scheduler 중복 실행 방어의 핵심 장치가 충분히 강하지 않았다.

---

## 2. 왜 위험했나

운영 환경에서는 job 겹침이 생각보다 현실적으로 발생할 수 있다.

- Cloud Scheduler가 다음 주기를 호출했는데 이전 실행이 아직 끝나지 않은 경우
- timeout이나 네트워크 문제 뒤 scheduler retry가 들어오는 경우
- 운영자가 수동으로 다시 실행하는 경우
- Cloud Run의 다른 인스턴스로 거의 동시에 요청이 들어오는 경우

이때 lock이 충분히 일찍 커밋되지 않으면, 두 실행이 모두 "내가 실행해도 된다"고 판단할 수 있다.

---

## 3. 근본 원인은 무엇이었나

문제의 핵심은 `job_lock` 테이블 스키마 부족이 아니었다.

테이블에는 이미 필요한 컬럼이 있었다.

- `job_name`
- `locked_until`
- `locked_by`
- `updated_at`

실제 문제는 런타임 동작 방식이었다.

1. `EventSyncService`와 `SnapshotService`가 job 전체를 하나의 트랜잭션으로 잡고 있었다.
2. `tryAcquire(...)`가 그 같은 트랜잭션 안에 참여했다.
3. lock 상태가 RPC 작업 전에 별도로 커밋되지 않았다.
4. acquire 로직이 read-then-write 방식이라 DB 원자성이 약했다.

즉 이 문제는 주로 아래 두 가지 문제였다.

- 트랜잭션 경계
- lock acquire 원자성

---

## 4. 어떻게 바꿨나

이번 수정은 세 가지를 같이 적용했다.

### 4-1. lock acquire를 별도 트랜잭션으로 커밋하게 바꿨다

`JobLockService.tryAcquire(...)`는 이제 아래처럼 동작한다.

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
```

의미는 이렇다.

- lock acquire는 자기만의 트랜잭션을 가진다.
- 호출이 끝나면 바로 커밋된다.
- 그 다음에야 바깥 job 로직이 계속 진행된다.

그래서 긴 RPC 작업이 시작되기 전에 lock 상태가 다른 요청에도 보이게 된다.

### 4-2. lock acquire를 SQL 한 번으로 처리하게 바꿨다

기존처럼

- `findById()`
- 자바에서 만료 여부 확인
- `save()`

이렇게 나누지 않고, PostgreSQL upsert 한 문장으로 처리하게 바꿨다.

```sql
INSERT INTO job_lock (job_name, locked_until, locked_by, updated_at)
VALUES (:jobName, :lockedUntil, :lockedBy, :now)
ON CONFLICT (job_name) DO UPDATE
  SET locked_until = :lockedUntil,
      locked_by = :lockedBy,
      updated_at = :now
WHERE job_lock.locked_until <= :now
```

이 쿼리 의미는 다음과 같다.

1. row가 없으면 insert 성공
2. row가 있지만 lease가 이미 만료됐으면 update 성공
3. row가 있고 lease도 아직 살아 있으면 아무 것도 업데이트하지 않음

즉, lock이 비어 있거나 만료된 경우에만 acquire가 성공한다.

### 4-3. release를 owner-aware 하게 바꿨다

각 실행은 이제 UUID 기반의 고유한 owner token을 하나 만든다.

release는 더 이상

- "job 이름만 보고 풀기"

가 아니다.

이제는

- "지금 이 실행이 아직 lock 주인일 때만 풀기"

가 된다.

그래서 release 조건에는 둘 다 들어간다.

- `job_name`
- `locked_by`

이렇게 해야 lease 만료 후 새 실행이 잡은 lock을 예전 실행이 실수로 풀어버리지 않는다.

---

## 5. 왜 `locked_by`와 UUID가 중요한가

이 부분이 제일 놓치기 쉽다.

예를 들어:

1. 실행 A가 lock 획득
2. 실행 A가 아직 작업 중
3. lease 만료
4. 실행 B가 같은 lock을 새로 획득
5. 실행 A가 늦게 끝나서 release 시도

이때 release가 `job_name`만 보고 동작하면, A가 B의 lock까지 풀어버릴 수 있다.

그래서 각 실행은 자기만의 owner token이 필요하다.

예:

- 실행 A owner: `uuid-a`
- 실행 B owner: `uuid-b`

release는 반드시 아래 조건일 때만 성공해야 한다.

```sql
where job_name = :jobName
  and locked_by = :lockedBy
```

이렇게 해야 실행 A가 실행 B의 lock을 해제하지 못한다.

---

## 6. 이 설계에서 release는 무슨 뜻인가

이 코드베이스는 lease-based lock을 사용한다.

즉 release는 row를 삭제하는 방식이 아니다.

release는 아래 뜻이다.

- `locked_until = now()`로 바꾸기

왜 이게 unlock이 되냐면 판단 기준이 이렇기 때문이다.

- `locked_until > now()` 이면 lock이 아직 살아 있음
- `locked_until <= now()` 이면 lock을 다시 잡을 수 있음

즉 unlock은 lease 종료 시점을 현재 시각으로 당겨서, 더 이상 유효하지 않은 lock으로 만드는 방식이다.

---

## 7. 이번 수정에서 바뀐 파일

핵심 R1 수정 파일:

- `backend/src/main/java/io/forkcast/backend/job/repository/JobLockRepository.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`

추가한 테스트 파일:

- `backend/src/test/java/io/forkcast/backend/job/service/JobLockServiceTest.java`

---

## 8. 어떻게 검증했나

아래 테스트를 추가했다.

1. 첫 acquire는 성공하고, lease가 살아있는 동안 두 번째 acquire는 실패해야 한다.
2. owner가 다른 release는 lock을 풀지 못해야 한다.
3. owner가 같은 release만 lock을 풀 수 있어야 한다.

실행한 명령:

```bash
./gradlew test --tests io.forkcast.backend.job.service.JobLockServiceTest
```

결과:

- 테스트 통과

---

## 9. 이 수정이 아직 해결하지 않는 것

이번 수정은 `R1`, 즉 lock commit timing과 lock ownership 문제를 해결하는 데 집중했다.

아직 완전히 해결하지 않는 것은 다음과 같다.

- `job_run` rollback 위험 (`R3`)
- `snapshot`의 긴 트랜잭션 범위 (`R4`)
- 아주 오래 걸리는 job에서의 lease 연장 문제
- 전체 scheduler flow 기준 엔드투엔드 overlap 테스트

즉, 이번 수정은 중요한 안전성 보강이지만 scheduler hardening 전체의 끝은 아니다.

---

## 10. 짧은 요약

문제는 이랬다.

- lock acquire 자체는 있었지만
- 충분히 빨리 커밋되지 않았고
- release도 owner 안전성이 부족했다.

해결은 이렇게 했다.

- lock acquire를 자기만의 트랜잭션에서 먼저 커밋
- acquire를 원자적 SQL 한 문장으로 처리
- `locked_by`가 현재 실행과 일치할 때만 release

그 결과 `job_lock`은 겹치는 scheduler 요청에 대해 훨씬 더 안전해졌다.
