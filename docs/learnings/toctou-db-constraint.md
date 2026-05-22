# TOCTOU 경쟁 조건 — DB Constraint로 원자성 위임

**관련 이슈:** H-1 (#11), H-2 (#13)  
**수정 PR:** #15, #16  
**날짜:** 2026-05-22

---

## 문제: TOCTOU (Time Of Check To Use)

TOCTOU는 "확인 시점"과 "사용 시점" 사이에 상태가 바뀌어 버그가 발생하는 패턴이다.

### 코드 예시 (수정 전)

```java
// H-2: StrategyPositionService
if (!strategyPositionRepository.existsById(tokenId)) {
    strategyPositionRepository.save(position);
}

// H-1: PendingTxService
if (!pendingTxRepository.existsByTxHash(txHash)) {
    pendingTxRepository.save(pendingTx);
}
```

### 왜 문제인가

```
Thread A: existsById → false
Thread B: existsById → false   ← A가 아직 save 하기 전
Thread A: save(position)       ← 성공
Thread B: save(position)       ← unique constraint violation!
```

`existsById`와 `save`는 별개의 트랜잭션 (or 같은 트랜잭션이어도 SQL 레벨에서 두 번 왕복).  
그 사이 gap에 다른 스레드/요청이 끼어들 수 있다.

---

## 해결책: DB Constraint에 원자성 위임

### H-2: ON CONFLICT DO NOTHING

```java
@Modifying
@Query(value = """
    INSERT INTO strategy_position (token_id, ...)
    VALUES (:tokenId, ...)
    ON CONFLICT (token_id) DO NOTHING
    """, nativeQuery = true)
int insertIfAbsent(...);
```

- INSERT와 "이미 있으면 무시" 처리가 하나의 SQL 문 = 원자적
- 반환값이 0이면 이미 존재 (정상 상황), 1이면 신규 삽입
- 예외 없이 조용히 처리됨

### H-1: DataIntegrityViolationException → 409

```java
// PendingTxService: check 제거, 바로 save
pendingTxRepository.save(pendingTx);

// GlobalExceptionHandler: DB violation을 의미있는 HTTP 응답으로 변환
@ExceptionHandler(DataIntegrityViolationException.class)
public ResponseEntity<ApiErrorResponse> handleDataIntegrityViolation(...) {
    return ResponseEntity.status(HttpStatus.CONFLICT)
        .body(ApiErrorResponse.of("DUPLICATE_TX_HASH", "이미 존재하는 트랜잭션입니다."));
}
```

- `save()` 호출 → DB unique constraint violation → Spring이 `DataIntegrityViolationException` 래핑
- GlobalExceptionHandler에서 잡아 409로 변환
- 클라이언트는 의미있는 에러 코드 수신

---

## 두 패턴의 차이

| 상황 | 적합한 패턴 |
|------|------------|
| 중복을 조용히 무시해야 함 (이벤트 재처리) | `ON CONFLICT DO NOTHING` |
| 중복을 에러로 클라이언트에 알려야 함 (API) | `save()` + `DataIntegrityViolationException` → 409 |

---

## 핵심 원칙

> **"DB가 이미 atomic하게 처리할 수 있는 것을 application level에서 중복 구현하지 마라."**

- SELECT → INSERT 2-step은 항상 race condition 가능성이 있다
- DB unique constraint + ON CONFLICT = 하나의 atomic operation
- application-level check는 성능 최적화(불필요한 write 줄이기)로만 사용, 정확성은 DB에 맡길 것
