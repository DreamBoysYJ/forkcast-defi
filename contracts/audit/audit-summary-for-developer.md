# 보안 감사 요약 — 2년차 개발자를 위한 가이드

**감사일:** 2026-05-20  
**대상:** `contracts/src/` 전체 프로덕션 솔리디티 파일

---

## 한 줄 요약

> `AccountFactory`의 접근 제어가 없어서 **지금 당장 누구나 모든 유저 계정을 탈취할 수 있다.**  
> 배포 전에 Critical 2개는 무조건 고쳐야 한다.

---

## 발견 항목 전체 현황

| ID | 심각도 | 한 줄 설명 |
|---|---|---|
| C-01 | **Critical** | `setRouter()`에 접근 제어 없음 — 누구나 라우터 교체 가능 |
| C-02 | **Critical** | `createAccount()`가 기존 계정을 덮어씀, 퍼미션도 없음 |
| H-01 | **High** | `UserAccount.execute()`가 모든 외부 호출 허용, 재진입 방어 없음 |
| H-02 | **High** | `SwapPriceLoggerHook`이 잘못된 슬롯 읽어서 가격 데이터 전부 쓰레기 |
| H-03 | **High** | `SafeCast.toInt128()` 하한 체크 없어서 음수 값 묵인 |
| M-01 | **Medium** | `createAccount()`가 기존 계정 덮어쓰는 별도 그리핑 벡터 |
| M-02 | **Medium** | 표준 미지원 ERC20(USDT 등)에서 transfer/approve 실패 |
| M-03 | **Medium** | 스왑 라우터 슬리피지 체크 로직 구멍 + deadline 없음 |
| M-04 | **Medium** | 훅이 최신 가격 1개만 저장하는데 마치 오라클처럼 카운팅 |
| L-01 | Low | `getPositions()` 계정 하나 실패하면 전체 배치 revert |
| L-02 | Low | `UserAccount` 오너 변경 불가 |
| L-03 | Low | pragma 버전이 `^`로 floating |
| L-04 | Low | `HookFactory` 퍼미션리스 배포, 이벤트 indexed 없음 |
| I-01 | Info | 라우터 모듈 3개 전부 스텁, `UniswapV4Module`은 문법 오류로 컴파일도 안 됨 |
| I-02 | Info | 테스트 파일 4개 전부 빈 placeholder |
| I-03 | Info | `TStore.sol` 아무데서도 import 안 함 |

---

## 지금 당장 고쳐야 할 것 (Critical / High)

### C-01 — `setRouter()`에 잠금이 없다

**왜 위험한가?**  
`AccountFactory.setRouter()`는 누가 불러도 실행된다. 이 함수가 바꾸는 `router` 주소는, 새로 만들어지는 모든 `UserAccount`가 "이 주소만 믿겠다"고 등록하는 대상이다. `UserAccount.execute()`는 라우터가 시키는 것이라면 어떤 외부 호출이든 실행한다. 즉, 라우터를 바꾸는 순간 그 이후에 생성된 모든 계정이 공격자 손에 넘어간다.

**지금 코드:**
```solidity
// AccountFactory.sol:12-14
function setRouter(address _router) external {  // ← 아무나 호출 가능!
    router = _router;
}
```

**고치는 방법:**
```solidity
address public immutable router;  // 변경 자체를 막는다
address public immutable owner;

constructor(address _router) {
    router = _router;
    owner = msg.sender;
}
```
라우터가 바뀔 일이 없다면 `immutable`로 만드는 게 제일 깔끔하다.

---

### C-02 — 아무나 남의 계정을 덮어쓸 수 있다

**왜 위험한가?**  
`createAccount(victim)`은 누구나 호출 가능하다. `accountOf[victim]`을 새 주소로 덮어쓴다. 피해자가 이미 돈을 넣어둔 원래 계정은 팩토리 매핑에서 사라지고, 프론트/인덱서는 새 계정(공격자 라우터를 가진)으로 유도된다.

**고치는 방법:**
```solidity
function createAccount(address user) external returns (address) {
    require(accountOf[user] == address(0), "already exists");  // ← 한 줄 추가
    // ...
}
```

추가로: `msg.sender == user`도 체크하면 자기 계정만 직접 만들 수 있어서 더 안전하다.

---

### H-01 — `UserAccount.execute()`가 재진입 방어 없이 뭐든 실행한다

**왜 위험한가?**  
"재진입(reentrancy)"은 외부 호출이 다시 내 함수를 부르는 패턴이다. 예를 들어 ERC777 같은 토큰은 `transfer` 중에 수신자에게 콜백을 날린다. 콜백 안에서 다시 `execute()`를 부를 수 있으면, 전송이 완료되기도 전에 잔액이 두 번 빠져나갈 수 있다.

현재 코드는 C-01이 해결되기 전까지 "라우터 = 공격자"이므로 이 취약점은 그 자체로 이미 Critical이다.

**고치는 방법:**  
프로젝트에 이미 `TStore.sol`(EIP-1153 트랜지언트 스토리지)이 있는데 아무데서도 안 쓴다. 여기에 쓰면 딱 맞다:

```solidity
bool private _entered;

modifier nonReentrant() {
    require(!_entered, "reentrant");
    _entered = true;
    _;
    _entered = false;
}

function execute(address target, uint256 value, bytes calldata data)
    external onlyRouter nonReentrant returns (bytes memory)
{
    // ...
}
```

더 장기적으로는 `execute()`를 `supply()`, `borrow()`, `swap()` 같은 타입화된 함수로 쪼개서, 실행 가능한 대상 자체를 화이트리스트로 잠그는 게 좋다.

---

### H-02 — 훅이 잘못된 슬롯을 읽어서 가격 데이터가 전부 엉터리다

**왜 위험한가?**  
`SwapPriceLoggerHook`은 스왑 후 현재 풀 가격을 기록해야 하는데, `extsload`에 넘기는 슬롯 주소가 틀렸다. 그 슬롯에는 실제 가격이 없으니, 온체인에 기록되는 모든 가격은 쓰레기 값이다. 지금은 인덱서/프론트에서만 이 값을 읽지만, 미래에 전략이 이 값을 기준으로 포지션을 조정하면 직접적인 자금 손실로 이어진다.

**고치는 방법:**  
v4가 제공하는 `StateLibrary`를 사용한다. 슬롯 계산을 직접 하지 않는다:

```solidity
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

using StateLibrary for IPoolManager;
using PoolIdLibrary for PoolKey;

// _afterSwap 내부에서:
(uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(key.toId());
```

`_readSlot0()`과 `_getCurrentPrice()` 함수는 삭제한다.

---

### H-03 — `SafeCast.toInt128()` 음수 체크 구멍

**왜 위험한가?**  
"SafeCast"라는 이름이 붙어 있지만, 실제로는 위에서만 막고 아래는 안 막는다. `int128`의 최솟값보다 더 작은 음수가 들어오면 조용히 통과되면서 완전히 다른 값으로 잘린다. v4 델타는 음수가 자주 나오므로, 미래 스왑 정산 코드에서 이 함수를 쓰면 금액 계산이 틀린다.

**고치는 방법:**
```solidity
function toInt128(int256 x) internal pure returns (int128) {
    if (x > type(int128).max || x < type(int128).min) revert Overflow();  // 양방향 체크
    return int128(x);
}
```

---

## 나중에 개선할 것 (Medium / Low)

| ID | 빠른 설명 | 수정 난이도 |
|---|---|---|
| M-02 | `SafeERC20` 써서 USDT 같은 비표준 토큰도 대응 | 쉬움 — import 하나 |
| M-03 | 스왑 방향 기반으로 output 계산 + deadline 파라미터 추가 | 보통 |
| M-04 | 훅 스토리지 목적 문서화 (인덱서용이면 이벤트만 남겨도 충분) | 쉬움 |
| L-01 | `getPositions()` try/catch로 배치 실패 격리 | 쉬움 |
| L-02 | `transferOwnership` + 2-step 패턴 추가 | 보통 |
| L-03 | `pragma solidity 0.8.26;`으로 버전 고정 | 매우 쉬움 |

---

## 수정 우선순위 Top 5

| 순위 | 항목 | 이유 |
|---|---|---|
| 1 | C-01: `setRouter` 접근 제어 추가 | 고치기 쉽고, 파급력이 가장 크다 |
| 2 | C-02: `createAccount` 덮어쓰기 방지 | 한 줄 추가로 해결 |
| 3 | H-02: `_readSlot0` → `StateLibrary`로 교체 | 가격 데이터 신뢰성 전체가 여기 달려있음 |
| 4 | H-01: `execute`에 `nonReentrant` + 타겟 화이트리스트 | 이미 있는 TStore 활용 |
| 5 | H-03: `toInt128` 양방향 체크 | 한 줄 수정, v4 통합 후 직접 영향권 |

---

## 테스트부터 시작하라

현재 테스트 파일 4개가 전부 비어있다. 위 취약점들을 잡으려면 아래 테스트부터 작성하는 것을 추천한다:

```solidity
// 우선순위 순서
function test_setRouter_onlyOwner() { ... }               // C-01 검증
function test_createAccount_cannot_overwrite() { ... }    // C-02 검증
function test_execute_nonRouter_reverts() { ... }         // H-01 검증
function test_hook_price_matches_getSlot0() { ... }       // H-02 검증
function test_safeCast_toInt128_lower_bound() { ... }     // H-03 검증
```

테스트가 통과해야 수정이 완료된 것이다. 테스트 없는 수정은 절반만 한 것이다.

---

## 현재 빌드 상태

`contracts/src/router/UniswapV4Module.sol`에 `function _swap(...)` 문법이 있어서 `forge build` 자체가 실패한다. 다른 것보다 이걸 먼저 고쳐야 빌드가 된다.

---

*전문 감사 리포트: `security-audit-report.md`*
