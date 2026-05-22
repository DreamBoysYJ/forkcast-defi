# 블록 타임스탬프 vs Instant.now()

**관련 이슈:** C-2 (#6)  
**수정 PR:** Wave 2 PR  
**날짜:** 2026-05-22

---

## 문제

```java
new PositionTimeline(
    tokenId, "OPENED", txHash, blockNumber,
    Instant.now(),   // ← 처리 시각 (잘못됨)
    ...
)
```

`Instant.now()`는 인덱서가 이벤트를 처리한 시각이다.  
블록체인 이벤트의 타임스탬프는 **블록이 생성된 시각**이어야 한다.

### 왜 문제인가

1. **재색인(reindex) 시 타임스탬프가 달라진다** — 같은 이벤트가 두 번 처리되면 다른 timestamp
2. **API 응답을 믿을 수 없다** — `/api/positions/{tokenId}/timeline`의 `eventTimestamp`가 부정확
3. **지연 처리 시 왜곡** — 서버가 1시간 늦게 이벤트를 처리하면 1시간 뒤 시각이 기록됨

---

## 해결: 블록 타임스탬프 캐시 + 전달

### 1. Web3jChainClient에 getBlockTimestamp() 추가

```java
public Instant getBlockTimestamp(long blockNumber) {
    return withRetry("ethGetBlockByNumber(" + blockNumber + ")", () -> {
        EthBlock response = web3j.ethGetBlockByNumber(
            new DefaultBlockParameterNumber(blockNumber), false).send();
        return Instant.ofEpochSecond(response.getBlock().getTimestamp().longValue());
    });
}
```

`eth_getBlockByNumber` 호출로 블록 헤더에서 `timestamp` 추출. Unix epoch seconds → `Instant`.

### 2. EventSyncService에서 캐시로 RPC 최소화

```java
Map<Long, Instant> blockTimestampCache = new HashMap<>();
// ...
Instant blockTimestamp = blockTimestampCache.computeIfAbsent(
    decodedEvent.blockNumber(), web3jChainClient::getBlockTimestamp);
positionTimelineService.appendOpened(decodedEvent, blockTimestamp);
```

같은 블록 번호에서 여러 이벤트가 오면 첫 번째만 RPC 호출, 나머지는 캐시 히트.

### 3. PositionTimelineService 시그니처 변경

```java
// Before
public void appendOpened(DecodedEvent event) { ... Instant.now() ... }

// After
public void appendOpened(DecodedEvent event, Instant blockTimestamp) { ... blockTimestamp ... }
```

---

## 핵심 원칙

> **"블록체인 이벤트의 시간 기준은 블록 타임이다. 처리 시각은 무관하다."**

- 온체인 데이터를 인덱싱할 때는 체인의 시간 기준(블록 타임)을 사용해야 한다
- `Instant.now()`는 인덱서 운영 시각에 종속 — 재처리 시 다른 값이 나옴
- 블록 타임스탬프는 같은 블록의 모든 이벤트가 공유 → 캐시로 RPC 절약
- `eth_getBlockByNumber`에서 `transactions: false`를 주면 트랜잭션 목록 없이 헤더만 가져와 더 빠름
