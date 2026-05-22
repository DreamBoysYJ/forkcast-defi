# RPC I/O를 DB 트랜잭션 밖으로 분리

**관련 이슈:** C-1 (#8)  
**수정 PR:** Wave 2 PR  
**날짜:** 2026-05-22

---

## 문제

```java
@Service
@Transactional          // 트랜잭션 시작
public class EventSyncService {
    public EventSyncResult run() {
        web3jChainClient.getLogs(...)  // RPC 호출 — 수백ms~수초
        web3jChainClient.getLogs(...)  // DB 커넥션이 열려 있는 상태
        // ... DB 쓰기 ...
    }
}
```

클래스 레벨 `@Transactional`은 `run()` 전체를 하나의 DB 트랜잭션으로 묶는다.  
RPC 응답을 기다리는 수백ms~수초 동안 DB 커넥션이 점유된다.

**왜 위험한가:** DB 커넥션 풀(기본 HikariCP: 10개)이 RPC 지연에 고스란히 노출된다.  
Infura RPC가 느리거나 retry가 3회 발생하면 ~ 7초 동안 커넥션 1개 점유 → 다수 동시 요청 시 커넥션 고갈.

---

## 해결: 클래스 레벨 `@Transactional` 제거

```java
@Service   // @Transactional 제거
@Slf4j
public class EventSyncService {
    public EventSyncResult run() {
        // RPC 호출: 트랜잭션 없음 ✓
        List<Log> logs = web3jChainClient.getLogs(...);
        
        // DB 쓰기: 각 downstream service가 자신의 @Transactional 보유
        rawChainEventService.saveIfAbsent(...);      // 자체 @Transactional
        positionTimelineService.appendOpened(...);   // 자체 @Transactional
    }
}
```

각 downstream service(`PositionTimelineService`, `RawChainEventService` 등)는 이미  
클래스 레벨 `@Transactional`을 갖고 있으므로 개별 DB 쓰기의 원자성은 유지된다.

---

## 트레이드오프

| | 기존 (단일 거대 트랜잭션) | 수정 후 (트랜잭션 분리) |
|---|---|---|
| DB 커넥션 점유 시간 | RPC 대기 포함 (길다) | DB 쓰기 시간만 (짧다) |
| 이벤트 처리 원자성 | 전체 배치 atomic | 이벤트별 atomic |
| 실패 시 재처리 | 전체 롤백 후 재시도 | 부분 실패 가능, 다음 실행에 catch-up |
| idempotency 요구 | 낮음 | 높음 (saveIfAbsent / ON CONFLICT 필수) |

이 프로젝트는 이미 모든 쓰기가 idempotent하므로 트레이드오프 수용 가능.

---

## 핵심 원칙

> **"DB 커넥션은 DB I/O에만 써야 한다. 네트워크 I/O와 함께 묶지 마라."**

- `@Transactional`은 DB 커넥션을 점유한다 — `@Transactional` 범위 안에서 외부 API/RPC 호출 금지
- Spring의 기본 `@Transactional` 전파는 `REQUIRED` — 메서드 진입 시 트랜잭션 없으면 생성
- HikariCP pool size (기본 10)는 트랜잭션 점유 시간에 민감하다
