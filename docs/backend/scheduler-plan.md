# Scheduler Plan (Draft)

> This document describes the v1 scheduler/runtime plan.
> The backend will run on Cloud Run.
> Recurring execution is triggered by Cloud Scheduler.

---

## 1. Scheduler overview

The backend has two recurring jobs:

1. `event-sync`
2. `snapshot`

These jobs are not run by an in-process Spring scheduler in production.

Instead:

Cloud Scheduler -> Cloud Run internal endpoint -> backend job execution

---

## 2. Why not Spring `@Scheduled` in production?

Cloud Run can scale to zero when there is no traffic.

Cloud Run can also scale out to multiple instances.

If we use only an in-process scheduler:

- The scheduler may not run when the instance is scaled down.
- Multiple instances may run the same job concurrently.
- It becomes harder to reason about job execution.

Therefore, v1 production runtime uses Cloud Scheduler.

---

## 3. Job list

### 3-1. `event-sync`

Purpose:

- Read Router and Hook events from chain logs
- Store raw chain events
- Update read models
- Reconcile pending tx hints when possible
- Advance sync cursor after successful processing

Endpoint:

- `POST /internal/jobs/event-sync`

Initial schedule:

- Every 5 minutes

Why 5 minutes?

- v1 prefers a conservative and simple runtime policy.
- More frequent execution increases downstream work:
  - Cloud Run executions
  - RPC calls
  - DB writes
- The backend is an off-chain indexer/query backend, not a real-time transaction executor.
- The main event-sync outputs are query/read-model data:
  - position history
  - pool price events
  - open position read models
- These can tolerate some delay in v1 if the sync logic stays explainable and stable.

---

### 3-2. `snapshot`

Purpose:

- Read current open position state
- Store periodic position snapshots
- Track values such as:
  - liquidity
  - amount0Now
  - amount1Now
  - currentTick
  - sqrtPriceX96
  - totalCollateralBase
  - totalDebtBase
  - healthFactor

Endpoint:

- `POST /internal/jobs/snapshot`

Initial schedule:

- Every 5 minutes

Why 5 minutes?

- Snapshot is a state-history feature, not the source of immediate position existence.
- Position existence/open-close state is handled by `event-sync`.
- Snapshot calls can become heavier as open position count increases.
- Too frequent snapshots may create many nearly identical rows.
- 5 minutes is a practical initial balance for v1.

---

## 4. Job responsibilities

### 4-1. `event-sync`

High-level flow:

1. Acquire `job_lock` for `event-sync`.
2. If lock is already held, return `202 SKIPPED`.
3. Load cursor from `sync_cursor`.
4. Determine target block range in backend code.
5. Read Router events.
6. Read Hook events.
7. Insert into `raw_chain_event`.
8. Update read models:
   - `strategy_position`
   - `position_timeline`
   - `pool_price_event`
9. Reconcile `pending_tx` if matching tx/event is found.
10. Update `sync_cursor`.
11. Insert `job_run`.
12. Release lock.

Notes:

- Cursor should advance only after successful processing.
- Duplicate events should be ignored by unique constraints.
- `(tx_hash, log_index)` is the key duplicate-prevention mechanism for raw events.
- Cloud Scheduler only triggers the internal endpoint.
- The backend computes block range at runtime from cursor state and latest block state.

---

### 4-2. `snapshot`

High-level flow:

1. Acquire `job_lock` for `snapshot`.
2. If lock is already held, return `202 SKIPPED`.
3. Query currently open positions from `strategy_position`.
4. For each open position, call lens/view function.
5. Insert into `position_snapshot`.
6. Insert `job_run`.
7. Release lock.

Notes:

- Snapshot does not create the primary position existence.
- Snapshot enriches known open positions with current state.
- Snapshot may be slightly delayed compared to event-sync.

---

## 5. Locking strategy

Use `job_lock`.

Required columns:

- `job_name`
- `locked_until`
- `locked_by`
- `updated_at`

Do not use only boolean `is_locked`.

Reason:

If the server dies while `is_locked = true`, the job may be stuck forever.

Using `locked_until` allows lock recovery.

Example logic:

1. If no row exists, acquire lock.
2. If `locked_until < now()`, acquire lock.
3. Otherwise, skip execution.

Implementation note:

- On normal completion, the backend should release the lock immediately instead of waiting for lease expiry.
- In practice, release can be implemented by updating `locked_until = now()`.
- Lease expiry remains the fallback recovery path only when the process dies before normal release.

Current decision:

- Current implementation acquires each job lock with a 2-minute lease.
- If the job finishes normally, whether success or failure, backend releases the lock immediately by setting `locked_until = now()`.
- If the process dies mid-run, the lock is recovered by lease expiry.

Current risk:

- The current implementation does not extend the lease while a job is running.
- If a future `event-sync` or `snapshot` run takes longer than 2 minutes, the lease may expire before the first run finishes, allowing a second run to acquire the same lock.
- This is acceptable for now because current local runs are short, but it should be revisited if block range or open position count grows.

Expected skip response:

- HTTP status: `202 Accepted`
- Body status: `SKIPPED`

---

## 6. Job run logging

Use `job_run`.

Store:

- job name
- started time
- finished time
- status
- error message
- processed block range if applicable

Purpose:

- Debugging
- Operational visibility
- Failure analysis

---

## 7. Cursor strategy

Use `sync_cursor`.

For v1, at minimum:

- `event-sync-finalized`

Possible future cursors:

- `event-sync-safe`
- `event-sync-latest`
- `backfill-router`
- `backfill-hook`

In v1:

- `event-sync` uses block cursor.
- `snapshot` usually does not need a block cursor.
- Snapshot uses `snapshot_at` and `job_run` for execution history.

### 7-1. Event-sync block range policy

In v1, block range is computed by backend logic, not by Cloud Scheduler.

Recommended runtime rule:

1. Read `latestBlock` from RPC.
2. Compute `safeHead = latestBlock - 5`.
3. If cursor exists:
   - `fromBlock = lastSyncedBlock + 1`
4. Otherwise:
   - create the cursor near `safeHead`, not at genesis
   - recommended bootstrap rule:
     - `initialCursor = max(0, safeHead - bootstrapWindowBlocks)`
     - `fromBlock = initialCursor + 1`
5. Set `toBlock = safeHead`
6. If `toBlock < fromBlock`, skip with no work
7. If sync succeeds, advance cursor to `toBlock`

Reason:

- The latest few blocks may still change.
- Avoiding the newest 5 blocks is a simple v1 safety policy.
- This avoids rewind/rebuild complexity in the first version.
- On first cloud deployment, starting from genesis can make one `eth_getLogs` range too large and fragile.
- Bootstrapping from the recent safe window is enough for the v1 "start from now" operating model.

### 7-2. Bootstrap config

The first `event-sync` bootstrap window is controlled by:

- `SYNC_BOOTSTRAP_WINDOW_BLOCKS`

Current default:

- `25`

Meaning:

- if the cursor does not exist yet, backend creates it near
  - `safeHead - SYNC_BOOTSTRAP_WINDOW_BLOCKS`
- so the first run only scans a recent safe range, not the whole chain from genesis

Where to set it:

- Cloud Run service env vars
- local IntelliJ Run/Debug configuration env vars
- local shell env when starting Spring Boot manually

Example values:

- `SYNC_BOOTSTRAP_WINDOW_BLOCKS=25`
- if you want a slightly wider first catch-up window, raise it to `50` or `100`

IntelliJ local example:

```text
RPC_URL=https://sepolia.infura.io/v3/...
STRATEGY_ROUTER_ADDRESS=0x8976fd44F134a93474c7809ff36De95FCbCc777a
HOOK_ADDRESS=0xf600DB53A6F76e3C8087524f48F35e46Ed7c8040
STRATEGY_LENS_ADDRESS=0xddc5349e0a354fe73edac0bdb15fba758be6f781
SCHEDULER_AUTH_ENABLED=false
APP_CORS_ALLOWED_ORIGINS=http://localhost:3000
SYNC_BOOTSTRAP_WINDOW_BLOCKS=25
```

---

## 8. Auth / endpoint protection

Internal job endpoints must not be publicly callable.

For v1, keep the current single-service API structure and protect only internal job URLs in backend code.

Chosen protection:

1. Cloud Scheduler HTTP job sends `Authorization: Bearer <OIDC ID token>`
2. The token is issued for a dedicated scheduler service account
3. Backend verifies:
   - Google ID token validity
   - expected `audience`
   - allowed scheduler service account email
4. If validation fails, backend returns `401` or `403`

Internal endpoints:

- `POST /internal/jobs/event-sync`
- `POST /internal/jobs/snapshot`

Public query APIs under `/api/**` stay open.

Local development may disable scheduler auth with config so job logic can be tested without real GCP-issued tokens.

---

## 9. Cost considerations

Main cost drivers:

1. DB
2. RPC provider
3. Cloud Run execution time
4. Overall sync work per execution

Cloud Scheduler itself is not the main cost driver.

Cloud Scheduler pricing is job-based, not per execution.

However, shorter intervals still increase:

- Cloud Run executions
- RPC calls
- DB work

Cost control strategies:

- Use address/topic-filtered log reads.
- Do not scan from block 0 repeatedly.
- Use cursor-based sync.
- Avoid reading the newest few blocks in v1.
- Snapshot only open positions.
- Keep snapshot interval slower than event-sync.
- Skip duplicate job execution with locks.

---

## 10. Initial v1 schedule

| Job | Endpoint | Initial interval | Purpose |
| --- | --- | --- | --- |
| `event-sync` | `POST /internal/jobs/event-sync` | 5 minutes | Sync chain events and update read models |
| `snapshot` | `POST /internal/jobs/snapshot` | 5 minutes | Store current state snapshots of open positions |

These intervals are initial values.

They can be tuned later based on:

- sync lag
- RPC cost
- DB growth
- frontend UX
- number of open positions

For v1, `event-sync` also uses a safe-head rule:

- `fromBlock = lastSyncedBlock + 1`
- `toBlock = latestBlock - 5`
