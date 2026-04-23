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

- Every 1 minute

Why 1 minute?

- Event sync affects user-visible history and open position lists.
- Too much delay creates poor UX.
- Cloud Scheduler works naturally with minute-level schedules.
- Event targets are narrow:
  - Router address
  - Hook address
  - selected event topics
- v1 should prefer a simple and explainable interval.

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
4. Determine target block range.
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

---

## 8. Auth / endpoint protection

Internal job endpoints must not be publicly callable.

Recommended protection:

1. Cloud Scheduler service account
2. OIDC authentication to Cloud Run
3. Optional secret header
4. Backend verifies internal access

Internal endpoints:

- `POST /internal/jobs/event-sync`
- `POST /internal/jobs/snapshot`

If unauthorized:

- return `401` or `403`

---

## 9. Cost considerations

Main cost drivers:

1. DB
2. RPC provider
3. Cloud Run execution time
4. Cloud Scheduler invocation count

Scheduler count itself is not the main cost.

Cost control strategies:

- Use address/topic-filtered log reads.
- Do not scan from block 0 repeatedly.
- Use cursor-based sync.
- Use reasonable block chunks.
- Snapshot only open positions.
- Keep snapshot interval slower than event-sync.
- Skip duplicate job execution with locks.

---

## 10. Initial v1 schedule

| Job | Endpoint | Initial interval | Purpose |
| --- | --- | --- | --- |
| `event-sync` | `POST /internal/jobs/event-sync` | 1 minute | Sync chain events and update read models |
| `snapshot` | `POST /internal/jobs/snapshot` | 5 minutes | Store current state snapshots of open positions |

These intervals are initial values.

They can be tuned later based on:

- sync lag
- RPC cost
- DB growth
- frontend UX
- number of open positions
