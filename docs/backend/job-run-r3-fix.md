# job_run R3 실패 이력 롤백 문제 정리

> 날짜: 2026-05-08
> 범위: `job_run` 실패 이력 롤백 문제(`R3`) 발견과 해결 정리

---

## 1. 이 문서의 목적

이 문서는 면접이나 복습 때 아래 내용을 한 번에 설명할 수 있도록 정리한 메모다.

- 어떤 문제가 있었는가
- 왜 그런 문제가 생겼는가
- 처음 떠올리기 쉬운 해결책이 왜 부족한가
- 최종적으로 어떻게 고쳤는가
- 어떻게 검증했는가

---

## 2. 문제를 어떻게 발견했나

배포 전 리스크 리뷰를 하면서 `job_run`의 역할을 다시 봤다.

`job_run`은 운영용 이력 테이블이다.

즉 다음 내용을 남겨야 한다.

- job이 언제 시작했는지
- 성공했는지 실패했는지
- 실패했다면 어떤 에러였는지
- `event-sync`라면 어느 block range를 처리 중이었는지

그런데 현재 코드 흐름을 보면, 실패 시 `markFailed(...)`를 호출하더라도 그 기록이 실제 DB에 남지 않을 수 있다는 점을 발견했다.

핵심 의심 포인트는 이것이었다.

- `EventSyncService.run()` / `SnapshotService.run()`이 큰 트랜잭션 하나를 잡고 있음
- `jobRunService.start(...)`와 `jobRunService.markFailed(...)`도 그 같은 트랜잭션에 합류하고 있음
- 마지막에 예외를 다시 던지면 바깥 트랜잭션이 통째로 롤백될 수 있음

즉 코드상으로는 "실패 기록을 남긴다"처럼 보이지만, 실제 DB에는 아무 것도 남지 않을 수 있었다.

---

## 3. 문제가 있던 기존 구조

기존 흐름을 단순화하면 이렇다.

1. `run()` 진입
2. `jobRunService.start(...)`
3. 실제 job 작업 수행
4. 예외 발생
5. `catch`에서 `jobRunService.markFailed(...)`
6. 예외를 다시 `throw`
7. 바깥 트랜잭션 전체 rollback

이때 `JobRunService`도 기본 `@Transactional(REQUIRED)`였기 때문에:

- `start(...)`의 insert
- `markFailed(...)`의 update

둘 다 바깥 `run()` 트랜잭션에 같이 묶였다.

그래서 마지막 rollback이 일어나면:

- `STARTED` row insert도 취소
- `FAILED` update도 취소

즉 실패 이력이 통째로 사라질 수 있었다.

---

## 4. 예시로 설명하면

예를 들어 `event-sync`가 block `100 ~ 120`을 처리 중이라고 하자.

원래 기대하는 흐름은 이렇다.

1. job 시작

```text
job_name=event-sync
status=STARTED
range_start_block=100
range_end_block=120
```

2. 중간에 `rpc timeout` 발생

3. 실패 기록 업데이트

```text
job_name=event-sync
status=FAILED
error_message=rpc timeout
range_start_block=100
range_end_block=120
```

하지만 기존 구조에서는 마지막 rollback 때문에 위 row 자체가 DB에 없을 수 있었다.

즉 실제로는 실패했는데, 운영자가 `job_run`을 보면 실패 이력이 비어 있는 상태가 생길 수 있었다.

---

## 5. 근본 원인은 무엇인가

근본 원인은 `job_run`을 비즈니스 로직과 같은 트랜잭션에 넣어둔 것이다.

이 테이블은 성격상 비즈니스 데이터라기보다 운영 메타데이터에 가깝다.

그런데 운영 메타데이터를 비즈니스 롤백에 같이 묶어버리면:

- 비즈니스 작업이 실패할 때
- 가장 필요한 운영 기록도 같이 사라진다

즉 문제의 본질은:

- `job_run`은 남아야 하는 이력인데
- 비즈니스 트랜잭션 실패에 같이 휩쓸려 롤백될 수 있었다

---

## 6. 중간에 떠올리기 쉬운 해결책이 왜 부족한가

처음에는 "그럼 `markFailed()`만 `REQUIRES_NEW`로 빼면 되지 않나?"라고 생각하기 쉽다.

하지만 그것만으로는 부족하다.

이유는 다음과 같다.

1. `start()`가 여전히 바깥 트랜잭션에 남아 있으면 `job_run` row가 아직 미커밋 상태다.
2. `markFailed()`가 `REQUIRES_NEW`로 새 트랜잭션에서 실행되면, 그 새 트랜잭션은 미커밋 row를 못 본다.
3. 그러면 `findById()`가 실패할 수 있다.

즉:

- `markFailed()`만 따로 빼는 건 반쪽 해결책이다.
- `start()`도 같이 따로 커밋돼야 한다.

---

## 7. 최종 해결 방향

핵심 아이디어는 단순하다.

### 7-1. job 시작 이력은 먼저 따로 커밋한다

`jobRunService.start(...)`를 `REQUIRES_NEW`로 바꿔서:

- `STARTED` row를 먼저 저장하고
- 바로 커밋되게 한다

이제 바깥 비즈니스 작업이 나중에 실패하더라도, 시작 이력은 이미 DB에 남아 있다.

### 7-2. 성공/실패 이력도 각각 따로 커밋한다

다음 메서드를 모두 `REQUIRES_NEW`로 바꿨다.

- `start(...)`
- `markSuccess(...)`
- `markFailed(...)`
- `markSkipped(...)`

이렇게 하면:

- 성공 시 `SUCCESS`가 별도 트랜잭션으로 저장
- 실패 시 `FAILED`가 별도 트랜잭션으로 저장
- 바깥 비즈니스 작업 rollback과 분리됨

### 7-3. catch 안에서 `markFailed()`가 또 실패해도 원래 예외를 유지한다

`catch` 안에서 `markFailed()`를 호출할 때도 작은 안전장치를 넣었다.

```java
catch (Exception e) {
  if (jobRun != null) {
    try {
      jobRunService.markFailed(jobRun.getId(), e.getMessage());
    } catch (Exception logFailure) {
      // 기록 실패가 원래 예외를 덮지 않게 한다.
    }
  }
  throw e;
}
```

이 코드는 `R3`의 본질 해결책이라기보다, 2차 예외 때문에 원래 실패 원인이 가려지지 않게 하는 보호막이다.

---

## 8. 결과적으로 트랜잭션이 어떻게 바뀌었나

이제 흐름은 이렇게 된다.

1. 바깥 `run()` 트랜잭션 시작
2. `start()` 호출
   - 별도 트랜잭션
   - `STARTED` 즉시 커밋
3. 실제 비즈니스 작업 수행
4. 실패하면 `markFailed()` 호출
   - 별도 트랜잭션
   - `FAILED` 즉시 커밋
5. 바깥 `run()` 트랜잭션은 실패로 rollback

여기서 중요한 점:

- 바깥 비즈니스 데이터는 롤백될 수 있음
- 하지만 `job_run` 이력은 이미 별도로 커밋되어 남아 있음

이게 이번 수정의 핵심 효과다.

---

## 9. 수정한 파일

핵심 수정 파일:

- `backend/src/main/java/io/forkcast/backend/job/service/JobRunService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`

추가 테스트 파일:

- `backend/src/test/java/io/forkcast/backend/job/service/JobRunServiceTest.java`

---

## 10. 어떻게 검증했나

이번에는 `JobRunServiceTest`를 추가해서 두 가지를 직접 검증했다.

### 10-1. 바깥 트랜잭션이 롤백돼도 `STARTED`가 남는지

- 바깥 `@Transactional` 메서드 안에서 `start()` 호출
- 일부러 예외를 던져 바깥 트랜잭션 rollback
- 그 뒤에도 `job_run` row가 `STARTED` 상태로 남는지 확인

### 10-2. 바깥 트랜잭션이 롤백돼도 `FAILED`가 남는지

- 바깥 `@Transactional` 메서드 안에서 `start()` 호출
- 이어서 `markFailed()` 호출
- 일부러 예외를 던져 바깥 트랜잭션 rollback
- 그 뒤에도 `job_run` row가 `FAILED` 상태로 남는지 확인

실행 명령:

```bash
./gradlew test --tests io.forkcast.backend.job.service.JobRunServiceTest
```

결과:

- 테스트 통과

---

## 11. 면접에서 짧게 말하면

짧게 설명하면 이렇게 말할 수 있다.

> `job_run`은 운영 이력 테이블인데, 기존에는 비즈니스 로직과 같은 트랜잭션에 묶여 있어서 job이 실패할 때 실패 기록까지 같이 롤백될 수 있었습니다. 그래서 `start`, `markSuccess`, `markFailed`, `markSkipped`를 모두 `REQUIRES_NEW`로 분리해 운영 이력이 별도로 커밋되도록 바꿨습니다. 그리고 바깥 트랜잭션이 롤백돼도 `STARTED`와 `FAILED` 기록이 남는 통합 테스트로 검증했습니다.`

---

## 12. 핵심 한 줄 요약

`job_run`은 비즈니스 롤백에 같이 휩쓸리면 안 되는 운영 이력이므로, lifecycle 기록 전체를 별도 트랜잭션으로 분리해 먼저/나중에 각각 독립 커밋되게 바꿨다.
