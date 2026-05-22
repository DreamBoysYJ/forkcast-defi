# RPC 재시도 — 지수 백오프

**관련 이슈:** H-3 (#9)  
**수정 PR:** Wave 2 PR  
**날짜:** 2026-05-22

---

## 문제

```java
} catch (IOException e) {
    throw new IllegalStateException("failed to fetch logs", e);
}
```

RPC 노드는 일시적으로 응답이 느리거나 네트워크 순단이 생길 수 있다.  
재시도 없이 바로 예외를 던지면 단순 순단으로도 sync 잡 전체가 실패한다.

---

## 해결: 지수 백오프 재시도

```java
private <T> T withRetry(String operation, RpcCall<T> call) {
    long delayMs = INITIAL_RETRY_DELAY_MS;  // 1000ms
    Exception lastException = null;

    for (int attempt = 1; attempt <= MAX_RETRY_ATTEMPTS; attempt++) {  // 최대 3회
        try {
            return call.execute();
        } catch (Exception e) {
            lastException = e;
            if (attempt < MAX_RETRY_ATTEMPTS) {
                log.warn("RPC call '{}' failed (attempt {}/{}), retrying in {}ms", ...);
                Thread.sleep(delayMs);
                delayMs *= 2;  // 1s → 2s → 4s
            }
        }
    }
    throw new IllegalStateException("... failed after 3 attempts", lastException);
}
```

재시도 패턴:
- 1회차 실패 → 1초 대기
- 2회차 실패 → 2초 대기
- 3회차 실패 → 예외 throw

최악 케이스 추가 지연: 1 + 2 = 3초 (3회 모두 실패 시)

---

## 핵심 설계 결정

**왜 Resilience4j를 쓰지 않았나?**  
의존성 추가 없이 직접 구현. 이 규모에서는 over-engineering.  
3회 고정 재시도면 네트워크 순단에 충분히 대응 가능.

**InterruptedException 처리:**
```java
} catch (InterruptedException ie) {
    Thread.currentThread().interrupt();  // interrupt flag 복원
    break;  // 재시도 루프 탈출
}
```
`Thread.sleep()` 중 interrupt 발생 시 flag를 복원해야 상위 코드가 인식 가능.

**함수형 인터페이스로 반복 제거:**
```java
@FunctionalInterface
private interface RpcCall<T> {
    T execute() throws Exception;
}
```
`getLatestBlockNumber`, `getBlockTimestamp`, `getLogs` 모두 동일한 retry 로직 재사용.

---

## 핵심 원칙

> **"외부 I/O는 항상 일시적 실패를 가정하라. 첫 번째 실패가 진짜 실패가 아닐 수 있다."**

- 1~3회 재시도 + 지수 백오프는 네트워크 코드의 기본값
- 재시도 횟수는 job 인터벌보다 훨씬 짧아야 함 (여기서는 job 2분, 재시도 최대 7초)
- 구조적 에러(잘못된 주소, 인증 실패)는 재시도해도 소용없음 — 실제로는 에러 분류가 더 정확하지만 이 규모에서는 단순 재시도로 충분
