# getLogs 블록 범위 제한 — Infura 무료 플랜 대응

**관련 이슈:** H-4 (#12)  
**수정 PR:** Wave 2 PR  
**날짜:** 2026-05-22

---

## 문제

```java
long rangeEndBlock = safeHead;  // 상한 없음
```

서버가 장시간 중단 후 재시작하면 cursor가 수천 블록 뒤에 있을 수 있다.  
단일 `eth_getLogs` 요청에 5000블록 범위를 요청하면 어떻게 될까?

### Infura 무료 플랜 제한

- `eth_getLogs` 요청당 최대 **2,000블록** 또는 **10,000개 로그**
- 초과 시: **에러도 아닌 빈 결과** 또는 **잘린 결과** 반환 (silent truncation)
- 즉, 2,001블록을 요청해도 HTTP 200이 오지만 데이터는 누락됨

---

## 해결: MAX_BLOCKS_PER_RUN 상한 적용

```java
private static final long MAX_BLOCKS_PER_RUN = 1_500L;  // 25% 여유

long rangeEndBlock = Math.min(safeHead, rangeStartBlock + MAX_BLOCKS_PER_RUN - 1);
```

2,000 한계의 75%인 1,500을 사용 — 여유 버퍼 확보.

### 따라잡기(catch-up) 동작

오래된 cursor를 가진 서버가 재시작되면:
```
run 1: cursor=100, 처리 100~1599
run 2: cursor=1600, 처리 1600~3099
run 3: cursor=3100, 처리 3100~4599
...
```

job 인터벌(2분)마다 1,500블록씩 따라잡는다.  
Sepolia 기준 약 12초/블록 → 1,500블록 = 5시간 분량을 한 번 실행에 처리.

---

## 핵심 원칙

> **"외부 서비스의 제한을 모르면 silent failure(조용한 실패)를 당한다."**

- Infura `eth_getLogs`의 2,000블록 제한은 에러로 나오지 않는다 — 데이터가 조용히 잘림
- RPC 제공자마다 다른 제한이 있으므로 사용 전 반드시 확인
- 제한 근처의 75~80%를 상한으로 설정하는 것이 실용적
- 한 번에 다 따라잡으려 하지 말고, 청크 단위로 나눠 안전하게 처리
