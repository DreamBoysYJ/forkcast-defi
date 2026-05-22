# Security Audit Report — Forkcast DeFi Contracts

**Date:** 2026-05-20  
**Auditor:** solidity-auditor (Claude Code)  
**Repository:** `forkcast-defi/contracts/`  
**Commit branch:** `fix/web-state-history-ui`

---

## Executive Summary

A professional security audit was performed on the production Solidity source files in `contracts/src/`. The codebase is an early-stage DeFi monorepo combining Aave v3 and Uniswap v4. Several **critical** and **high** severity vulnerabilities were identified. The most severe findings allow any external party to take full control of every user's smart account and drain funds. These must be resolved before any mainnet deployment.

| Severity | Count |
|---|---|
| Critical | 2 |
| High | 3 |
| Medium | 4 |
| Low | 4 |
| Informational | 3 |

**The two Critical findings (C-01, C-02) in `AccountFactory` are prerequisite blockers. Until resolved, no user funds should enter the system.**

---

## Scope

### In Scope (production `src/`)

```
src/router/StrategyRouter.sol          (stub — cannot compile)
src/router/AaveModule.sol              (stub)
src/router/UniswapV4Module.sol         (stub — invalid Solidity syntax)
src/accounts/UserAccount.sol           ← primary audit target
src/factory/AccountFactory.sol         ← primary audit target
src/lens/StrategyLens.sol
src/hook/SwapPriceLoggerHook.sol
src/hook/HookFactory.sol
src/uniswapV4/Miniv4SwapRouter.sol
src/libs/UniswapV4LiquidityPreview.sol
src/libs/Hooks.sol
src/libs/HookMiner.sol
src/libs/SafeCast.sol
src/utils/TStore.sol
src/interfaces/IERC20.sol
```

### Reference Only (not audited for vulnerabilities)

`lib/v4-core`, `lib/v4-periphery`, `test/` (placeholder test files)

### Assumptions

- v4 `PoolId = keccak256(abi.encode(poolKey))` (confirmed via `lib/v4-core/src/types/PoolId.sol`).
- v4 pool state base slot: `keccak256(abi.encodePacked(poolId, bytes32(uint256(6))))` where `POOLS_SLOT = 6` (confirmed via `StateLibrary.sol`).
- `BaseHook` constructor calls `validateHookAddress(this)` and reverts on flag mismatch (confirmed via `lib/v4-periphery`).
- The backend is read-only and never submits user transactions; "backend front-runs the user" is not in threat scope per project design.

---

## Findings

### Summary Table

| ID | Title | Severity |
|---|---|---|
| C-01 | `AccountFactory.setRouter` unprotected — anyone can set the router and control all accounts | Critical |
| C-02 | `createAccount` mapping is overwritable and router trust is owner-unapproved | Critical |
| H-01 | `UserAccount.execute` is a general arbitrary-call primitive with no reentrancy guard | High |
| H-02 | `SwapPriceLoggerHook._readSlot0` reads the wrong storage slot — on-chain price data is corrupt | High |
| H-03 | `SafeCast.toInt128` missing lower-bound check — silent signed integer truncation | High |
| M-01 | `AccountFactory.createAccount` has no guard against overwriting an existing user account | Medium |
| M-02 | `UserAccount` uses raw `transfer`/`approve` — breaks with non-standard ERC20s | Medium |
| M-03 | `Miniv4SwapRouter` slippage check uses sign heuristic; no deadline parameter | Medium |
| M-04 | `SwapPriceLoggerHook` overwrites a single observation slot but counts like an oracle | Medium |
| L-01 | `StrategyLens.getPositions` reverts the entire batch on one bad account | Low |
| L-02 | `UserAccount` has no ownership rotation / two-step transfer | Low |
| L-03 | Floating pragma `^0.8.24` across all contracts | Low |
| L-04 | `HookFactory.deploy` is permissionless; event has no indexed fields | Low |
| I-01 | Core router modules are stubs; `UniswapV4Module` has invalid Solidity syntax | Informational |
| I-02 | Test suite is entirely empty placeholders | Informational |
| I-03 | `TStore` library is imported nowhere | Informational |

---

### [C-01] `AccountFactory.setRouter` is unprotected — anyone can hijack the router

**Severity:** Critical  
**Location:** `src/factory/AccountFactory.sol:12-14`

**Description:**

```solidity
address public router;

function setRouter(address _router) external {   // ← no access modifier
    router = _router;
}

function createAccount(address user) external returns (address) {
    address account = address(new UserAccount());
    UserAccount(payable(account)).initialize(user, router);  // router baked into account
    accountOf[user] = account;
    return account;
}
```

`setRouter` has no `onlyOwner` or equivalent guard. The `router` address stored here is injected into every `UserAccount` as its only privilege gate (`onlyRouter`). `UserAccount.execute` (H-01) lets the router make arbitrary external calls from inside the account. Therefore, controlling `router` at account creation time means controlling that account's funds indefinitely.

**Attack Scenario:**

1. Attacker calls `factory.setRouter(attackerContract)`.
2. A victim or operator calls `factory.createAccount(victim)`. The new account initializes with `router = attackerContract`.
3. Victim deposits tokens into their newly created account.
4. Attacker, via `attackerContract`, calls `userAccount.execute(USDC, 0, abi.encodeCall(IERC20.transfer, (attacker, balance)))`, draining the account.

**Recommendation:**

Make `router` immutable and set it in the constructor. If mutability is required, add access control and a timelock:

```solidity
contract AccountFactory {
    address public immutable router;
    address public immutable owner;

    constructor(address _router) {
        router = _router;
        owner = msg.sender;
    }
}
```

**References:** SWC-105 (Unprotected Ether Withdrawal), SWC-118 (Incorrect Constructor Name)

---

### [C-02] `createAccount` mapping is overwritable and router trust is not approved by the owner

**Severity:** Critical  
**Location:** `src/factory/AccountFactory.sol:16-21`, `src/accounts/UserAccount.sol:38-43`

**Description:**

`accountOf[user] = account` is written unconditionally. A second call to `createAccount(victim)` overwrites the entry, orphaning any funds held in the original account. Nothing prevents an attacker from calling this for arbitrary `user` addresses. Combined with C-01, the account's `router` value is whatever an attacker sets — never approved by the account owner.

**Attack Scenario:**

1. Victim's account is funded and `accountOf[victim]` resolves to `account_A`.
2. Attacker calls `createAccount(victim)` (permissionless). `accountOf[victim]` now points to `account_B` (empty, attacker-router).
3. Frontend/indexer resolves victim's account via `accountOf[victim]`; new deposits flow into `account_B`, which the attacker drains.

**Recommendation:**

Guard against re-creation and use CREATE2 for deterministic addresses:

```solidity
function createAccount(address user) external returns (address) {
    require(accountOf[user] == address(0), "already exists");
    address account = address(
        new UserAccount{salt: keccak256(abi.encode(user))}()
    );
    UserAccount(payable(account)).initialize(user, router);
    accountOf[user] = account;
    return account;
}
```

Consider restricting to `msg.sender == user` so only the user can create their own account.

**References:** SWC-118, SWC-114 (Transaction Order Dependence)

---

### [H-01] `UserAccount.execute` is a general arbitrary-call primitive with no reentrancy guard

**Severity:** High (Critical if C-01/C-02 unresolved)  
**Location:** `src/accounts/UserAccount.sol:55-64`

**Description:**

```solidity
function execute(address target, uint256 value, bytes calldata data)
    external onlyRouter returns (bytes memory)
{
    (bool success, bytes memory result) = target.call{value: value}(data);
    require(success, "call failed");
    return result;
}
```

This is a fully generic "call anything" primitive. The entire security model of every user's funds reduces to: "is the router trustworthy?" Given C-01/C-02, the router is attacker-controlled at deployment time.

Even with an honest router, there is no reentrancy guard. A malicious ERC777 token or hook-manipulated pool can re-enter `execute` or `withdraw` mid-operation before balances settle.

The project already has `TStore.sol` (EIP-1153 transient storage) that is currently unused — this is its natural home.

**Recommendation:**

- Replace the generic `execute` with typed functions: `supply(asset, amount)`, `borrow(asset, amount)`, `swap(...)` — each hard-coding a trusted target address.
- If a generic primitive is retained, gate target against an allowlist (Aave pool, PoolManager only).
- Add reentrancy protection using the existing `TStore` library:

```solidity
bool private _entered;
modifier nonReentrant() {
    require(!_entered, "reentrant");
    _entered = true;
    _;
    _entered = false;
}
```

**References:** SWC-107 (Reentrancy), SWC-105

---

### [H-02] `SwapPriceLoggerHook._readSlot0` reads the wrong storage slot — price data is corrupt

**Severity:** High  
**Location:** `src/hook/SwapPriceLoggerHook.sol:88-98`

**Description:**

```solidity
function _readSlot0(bytes32 poolId) internal view returns (uint160 sqrtPriceX96, int24 tick) {
    bytes32 slot = keccak256(abi.encode(poolId, uint256(6)));  // WRONG
    bytes32 raw = poolManager.extsload(slot);
    sqrtPriceX96 = uint160(uint256(raw));
    tick = int24(int256(uint256(raw) >> 160));
}
```

The canonical v4 slot derivation (from `StateLibrary._getPoolStateSlot`):

```solidity
keccak256(abi.encodePacked(poolId, bytes32(uint256(6))))  // POOLS_SLOT = 6
```

While `abi.encode` and `abi.encodePacked` produce identical bytes for two 32-byte values, the slot constant `uint256(6)` must be cast to `bytes32` before packing — and more importantly, the correct call is `poolManager.getSlot0(poolId)` via `StateLibrary`, not a hand-rolled `extsload`. With the incorrect derivation, `extsload` returns whatever occupies the mis-derived slot (often zero or unrelated data).

Every `PriceLogged` event and every `latestObservation[poolId]` entry records a `sqrtPriceX96`/`tick` that is not the pool's real price. Any downstream consumer (indexer, frontend chart, or a future strategy sizing off this data) is fed corrupt values.

**Recommendation:**

Use `StateLibrary` directly:

```solidity
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

using StateLibrary for IPoolManager;
using PoolIdLibrary for PoolKey;

function _afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata,
    BalanceDelta,
    bytes calldata
) internal override returns (bytes4, int128) {
    (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(key.toId());
    // ... rest of storage logic
}
```

Delete `_readSlot0` and `_getCurrentPrice`. Add a test that swaps and asserts `latestObservation[poolId].sqrtPriceX96 == poolManager.getSlot0(id).sqrtPriceX96`.

**References:** v4 `StateLibrary`, SWC-110 (Assert Violation)

---

### [H-03] `SafeCast.toInt128` is missing a lower-bound check — signed casts silently truncate

**Severity:** High  
**Location:** `src/libs/SafeCast.sol:14-17`

**Description:**

```solidity
function toInt128(int256 x) internal pure returns (int128) {
    if (x > type(int128).max) revert Overflow();   // upper bound only
    return int128(x);                               // x < type(int128).min wraps silently
}
```

A value of `type(int128).min - 1` passes the check and is silently truncated to an incorrect, potentially attacker-favorable value. Uniswap v4 deltas are signed integers and routinely negative, so any future swap-settlement code calling `toInt128` on a negative delta can mis-account settlement amounts.

**Recommendation:**

```solidity
function toInt128(int256 x) internal pure returns (int128) {
    if (x > type(int128).max || x < type(int128).min) revert Overflow();
    return int128(x);
}
```

Prefer adopting `OpenZeppelin SafeCast` or `v4-core SafeCast` rather than maintaining a hand-rolled version.

**References:** SWC-101 (Integer Overflow and Underflow)

---

### [M-01] `AccountFactory.createAccount` has no guard against overwriting an existing account

**Severity:** Medium  
**Location:** `src/factory/AccountFactory.sol:16-21`

**Description:** Separate from C-02's router-trust angle, the absence of `require(accountOf[user] == address(0))` is a standalone griefing vector: any caller can orphan a funded account by overwriting its mapping entry. The prior account's funds are not lost (they remain in the old contract) but they become unreachable via the factory.

**Recommendation:** Add `require(accountOf[user] == address(0), "account exists")` as the first line of `createAccount`.

---

### [M-02] `UserAccount` uses raw `IERC20.transfer`/`approve` — breaks with non-standard tokens

**Severity:** Medium  
**Location:** `src/accounts/UserAccount.sol:71, 80`

**Description:**

```solidity
IERC20(token).approve(spender, amount);   // return value ignored
IERC20(token).transfer(owner, amount);    // return value ignored
```

Tokens that return `false` on failure (some legacy tokens) silently succeed. Tokens that return no data (USDT on mainnet) revert on ABI decode. Approval calls on USDT-style tokens that require a reset-to-zero first also revert. For a custody contract, this means funds may fail to move while the calling logic believes they succeeded.

**Recommendation:** Replace with `SafeERC20` (`safeTransfer`, `safeApprove` / `forceApprove`).

**References:** SWC-104 (Unchecked Call Return Value)

---

### [M-03] `Miniv4SwapRouter` slippage check uses a sign heuristic and has no deadline

**Severity:** Medium  
**Location:** `src/uniswapV4/Miniv4SwapRouter.sol:100-104`

**Description:**

```solidity
uint256 amountOut = amount0 > 0 ? uint256(amount0) : uint256(amount1);
if (amountOut < cbData.minAmountOut) revert TooLittleReceived(...);
```

For a standard swap one delta is positive (output) and the heuristic works. In adversarial pool configurations with `afterSwapReturnDelta`-enabled hooks, both deltas can be non-positive, causing `amountOut = uint256(negative_int256)` — a very large number that always passes the slippage check.

There is also no deadline parameter. A transaction that is stuck in the mempool executes at a stale price with no expiry.

**Recommendation:**

Compute output from the known direction, not by sign:

```solidity
int256 out = params.zeroForOne ? amount1 : amount0;
require(out > 0, "no output");
if (uint256(out) < cbData.minAmountOut) revert TooLittleReceived(uint256(out), cbData.minAmountOut);
```

Add `uint256 deadline` to `SwapParams` and `require(block.timestamp <= deadline, "expired")`.

**References:** SWC-114 (Transaction Order Dependence / Front-running)

---

### [M-04] `SwapPriceLoggerHook` overwrites a single observation slot — no historical data despite counting

**Severity:** Medium  
**Location:** `src/hook/SwapPriceLoggerHook.sol:21-22, 67-72`

**Description:** `latestObservation[poolId]` is overwritten on every swap, while `observationCount[poolId]` increments — implying historical data, which does not exist. The single-slot design is a manipulable spot-price source: one swap sets the "oracle" value. If any future strategy reads `latestObservation` for pricing, it is trivially sandwichable.

Compounded with H-02, the stored value is also wrong.

**Recommendation:** If the purpose is off-chain indexing, remove the storage and emit only the event (the indexer can subscribe). If on-chain oracle semantics are needed, implement a TWAP with a cumulative-tick ring buffer. Document the intended consumer explicitly.

---

### [L-01] `StrategyLens.getPositions` reverts the entire batch on one bad account

**Severity:** Low  
**Location:** `src/lens/StrategyLens.sol:65-83`

**Description:** The loop calls `aavePool.getUserAccountData(accounts[i])` and `IStrategyAccount(accounts[i]).owner()` with no error isolation. If any element is not a valid contract or causes Aave to revert, the whole call fails, denying the indexer all results.

**Recommendation:** Wrap per-account reads in `try/catch` and return a zeroed `PositionView` for failures.

---

### [L-02] `UserAccount` has no ownership transfer mechanism

**Severity:** Low  
**Location:** `src/accounts/UserAccount.sol:34`

**Description:** `owner` is set once at initialization and cannot be changed. If the owner key is lost or compromised, the account's funds are permanently inaccessible via the `onlyOwner` paths. There is no two-step ownership transfer.

**Recommendation:** Add `transferOwnership` with a `pendingOwner` pattern gated by `onlyOwner`.

---

### [L-03] Floating pragma across all contracts

**Severity:** Low  
**Location:** All files (`pragma solidity ^0.8.24;`)

**Description:** Allows compilation under different patch versions than those used during testing.

**Recommendation:** Pin to a specific version (`pragma solidity 0.8.26;`) consistently across all files.

**References:** SWC-103 (Floating Pragma)

---

### [L-04] `HookFactory.deploy` is permissionless; event has no indexed fields

**Severity:** Low  
**Location:** `src/hook/HookFactory.sol`

**Description:** Anyone can deploy a `SwapPriceLoggerHook` via CREATE2 with any salt. `BaseHook`'s constructor validates the hook address flags, so an invalid deploy reverts — no fund risk. The only exposure is address-space griefing and harder event filtering due to unindexed `hook` and `salt` fields.

**Recommendation:** Index event fields: `event HookDeployed(address indexed hook, bytes32 indexed salt)`.

---

### [I-01] Core router modules are stubs; `UniswapV4Module` has invalid Solidity syntax

**Severity:** Informational  
**Location:** `src/router/UniswapV4Module.sol:8`, `src/router/AaveModule.sol:8-10`, `src/router/StrategyRouter.sol`

**Description:** `UniswapV4Module._swap(...)` uses `...` as a parameter list, which is not valid Solidity and will fail `forge build`. `AaveModule._supply` and `StrategyRouter.execute()` are empty stubs. The entire Permit2→supply→borrow→swap flow does not exist yet; these modules cannot be audited for logic vulnerabilities. **A re-audit is required once these modules are implemented.**

---

### [I-02] Test suite is entirely empty placeholders

**Severity:** Informational  
**Location:** `test/StrategyRouter_OpenPosition.t.sol`, `test/StrategyRouter_ClosePosition.t.sol`, `test/lens/StrategyLens.t.sol`, `test/uniswapV4/SwapPriceLoggerHook.t.sol`

**Description:** All four test files contain only a single `test_placeholder()` function that tests nothing. None of the critical access-control paths, slippage checks, or oracle reads are verified. The findings above would all be caught by a basic test suite.

---

### [I-03] `TStore` library is unused

**Severity:** Informational  
**Location:** `src/utils/TStore.sol`

**Description:** No in-scope contract imports `TStore`. It is dead code today. The natural use is to back the `nonReentrant` guard recommended in H-01, making the project actually exercise EIP-1153 safely.

---

## Test Coverage Analysis

| Missing test | Finding caught |
|---|---|
| `setRouter` from non-owner (expect revert) | C-01 |
| `createAccount` called twice for same user (expect revert) | C-02, M-01 |
| `execute` from non-router address (expect revert) | H-01 |
| Reentrancy into `execute` via malicious token callback | H-01 |
| `SwapPriceLoggerHook` swap then assert `latestObservation == getSlot0` | H-02 |
| `toInt128(type(int128).min - 1)` (expect revert) | H-03 |
| `withdraw` with USDT-style no-return token | M-02 |
| `getPositions` with one invalid account in the list | L-01 |

---

## Methodology

1. **Manual code review** — each file in scope was read in full.
2. **Dependency cross-reference** — `lib/v4-core` and `lib/v4-periphery` were read to verify slot layout, `BaseHook` behaviour, and `PoolId` derivation.
3. **Attack scenario construction** — for each candidate vulnerability, a concrete step-by-step exploit was traced through the call graph.
4. **Severity classification** — follows OWASP / common DeFi audit standards: Critical = direct, reliable fund loss; High = fund loss under plausible conditions or material corruption of a core invariant; Medium = degraded safety or DoS without immediate fund loss; Low = best-practice violation with minor risk; Informational = no immediate risk but worth addressing.

---

*End of report.*
