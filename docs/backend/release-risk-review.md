# Backend Release Risk Review

> Date: 2026-05-08
> Scope: current v1/v2 integrated backend code review before broader GCP rollout

---

## 1. Purpose

This note captures the backend risks that matter most before wider deployment.

The goal is not to list every possible cleanup item.

The goal is to separate:

- release blockers
- known debt that may be tolerated for now
- later optimization work

---

## 2. Release Blockers

### R1. `job_lock` is not safely committed before RPC work starts

Relevant code:

- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`

Problem:

- `EventSyncService` and `SnapshotService` hold the whole run in one transaction.
- `jobLockService.tryAcquire(...)` joins that same transaction.
- The lock row is not durably committed before long RPC work begins.
- A second Cloud Run request may still observe the old lock state and acquire the same job.

Why this matters:

- This weakens the main protection against duplicate scheduler runs.
- Cloud Scheduler retry or manual re-run can overlap with an in-flight job.
- Once runtime gets slower, this becomes much more dangerous.

Recommended direction:

- Move lock acquire/release into separately committed transaction boundaries.
- Prefer atomic DB acquire logic rather than `findById` then mutate in memory.
- Example direction:
  - conditional `UPDATE ... WHERE locked_until <= now()`
  - or `INSERT ... ON CONFLICT ... DO UPDATE ... WHERE locked_until <= now()`

Status:

- treat as release blocker

---

### R2. Pre-bootstrap close/fee events can poison `event-sync`

Relevant code:

- `backend/src/main/java/io/forkcast/backend/position/service/StrategyPositionService.java`
- `backend/src/main/java/io/forkcast/backend/position/service/PositionTimelineService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`

Problem:

- Current runtime policy bootstraps from a recent block window.
- Older positions may therefore have no local `strategy_position` row.
- If later `PositionClosed` or `FeesCollected` arrives for such a position, current code throws.
- That fails `event-sync`, prevents cursor advance, and the same log can fail every retry.

Why this matters:

- One old-but-valid on-chain event can stall the whole sync pipeline.
- This is more than a missing edge case; it can stop the system from progressing.

Current deployment assumption:

- For the current release, the team assumes production usage begins after deployment.
- In other words, positions that matter operationally are expected to be opened after this backend starts observing events.
- Under that assumption, this risk is much lower in the immediate rollout because the problematic "position opened before local bootstrap, but closed/fees arrives later" path should not occur in normal usage.

Recommended direction:

- Choose one explicit policy:
  - lazy reconstruction of missing `strategy_position`
  - skip with audit row / error record and continue
  - one-time backfill / seed of already-open positions before production use
- Do not leave this as an implicit exception path.

Status:

- general-case risk: release blocker
- current scoped rollout assumption: lower immediate risk, but keep documented as a guardrail if that assumption changes

---

## 3. High-Priority Operational Risks

### R3. Failed `job_run` history is likely rolled back away

Relevant code:

- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobRunService.java`

Problem:

- The service creates `job_run`, does work, marks failure, then rethrows.
- Because the whole method is transactional, the rethrow rolls back both:
  - the initial `job_run` insert
  - the later `markFailed(...)`

Why this matters:

- Operators lose failure history exactly when they need it most.
- Debugging production incidents becomes harder.

Recommended direction:

- Persist `job_run` lifecycle changes in separate transaction boundaries.
- At minimum, ensure failed runs survive rollback of business work.

Status:

- not as urgent as R1/R2, but should be fixed early

---

### R4. `snapshot` work is unbounded inside one long transaction

Relevant code:

- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`

Problem:

- It loads every open position.
- It performs per-position RPC calls.
- It saves snapshots one by one.
- All of that happens under one transaction and one 2-minute lease assumption.

Why this matters:

- runtime grows with open position count
- one slow RPC stretches the whole transaction
- one bad position can fail the entire batch
- lock overlap risk grows as total duration grows

Recommended direction:

- Split work into chunks.
- Keep RPC-heavy work outside the largest write transaction where possible.
- Persist snapshots in smaller batches.
- Revisit lock lease assumptions once real volume is known.

Status:

- high-priority risk

---

## 4. Known Debt That Is Acceptable For Now

These items are important but do not currently look like immediate release blockers by themselves.

### D1. `event_timestamp` is still runtime ingest time

Relevant code:

- `backend/src/main/java/io/forkcast/backend/chain/service/RawChainEventService.java`
- `backend/src/main/java/io/forkcast/backend/position/service/PositionTimelineService.java`
- `backend/src/main/java/io/forkcast/backend/pool/service/PoolPriceEventService.java`

Current state:

- uses `Instant.now()`
- not actual block timestamp

Impact:

- timeline ordering and display can diverge from true chain time
- acceptable as temporary v1 simplification if clearly documented

---

### D2. Duplicate prevention uses extra round trips

Relevant code:

- `PendingTxService`
- `RawChainEventService`
- `PoolPriceEventService`

Current state:

- `existsBy...` check
- then `save(...)`

Impact:

- more DB round trips
- race window remains unless DB unique constraint is the final guard

Suggested later improvement:

- move toward insert-first / upsert patterns backed by unique constraints

---

### D3. Test coverage is still too thin

Current state:

- almost no meaningful backend tests yet

Impact:

- regression risk is high around lock/cursor/retry behavior

Most valuable future test targets:

- concurrent job acquire behavior
- cursor advance only on success
- missing historical position during close/fees event
- snapshot failure isolation behavior

---

## 5. Recommended Work Order

### Phase 1. Fix before trusting wider runtime

1. Make `job_lock` acquisition atomic and independently committed.
2. Decide and implement policy for missing historical `strategy_position` on close/fees.
3. Make failed `job_run` history persist even when business work rolls back.

### Phase 2. Stabilize runtime shape

1. Chunk `snapshot` work.
2. Revisit lease duration / lease extension policy.
3. Add minimal operational tests for lock/cursor/failure paths.

### Phase 3. Later optimization

1. reduce `exists + save` patterns
2. replace ingest-time timestamps with block timestamps
3. improve backfill / replay tooling
4. add stronger observability and recovery tooling

---

## 6. Suggested Decision Notes

Before more deployment work, the team should explicitly answer:

1. What is the intended policy when a close/fees event arrives for a position that was opened before local bootstrap?
2. Is a one-time seed/backfill of current open positions required before production usage, or is the rollout assumption strictly "only positions opened after deployment matter"?
3. Do we want fail-fast behavior for projection inconsistencies, or continue-with-audit behavior?
4. What maximum runtime should `event-sync` and `snapshot` be designed for in Cloud Run?

---

## 7. Bottom Line

The biggest current concern is not micro-optimization.

The biggest current concern is runtime safety:

- safe locking
- safe cursor progression
- safe handling of pre-bootstrap historical positions
- preserved operational failure history

After those are addressed, performance and cleanup work become much safer to do incrementally.
