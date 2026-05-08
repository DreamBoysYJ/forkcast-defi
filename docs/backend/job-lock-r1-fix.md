# Job Lock R1 Fix Note

> Date: 2026-05-08
> Scope: `job_lock` release blocker (`R1`) explanation and fix summary

---

## 1. What Was The Problem?

`event-sync` and `snapshot` both rely on `job_lock` to prevent overlapping runs.

The original code had a risky shape:

1. job starts
2. `jobLockService.tryAcquire(...)` runs
3. long RPC work starts
4. transaction commits only at the end

This meant the lock row was not durably committed before the long-running work began.

As a result, another request could still arrive and observe the old lock state.

That weakens the main protection against duplicate scheduler execution.

---

## 2. Why This Was Dangerous

In production, overlap can happen in realistic situations:

- Cloud Scheduler triggers the next run while the previous run is still running
- Scheduler retry happens after timeout or network issue
- operator manually re-runs the job
- Cloud Run serves near-simultaneous requests on different instances

If the lock is not committed early enough, two runs may both believe they can proceed.

---

## 3. Root Cause

The root cause was not the `job_lock` table schema itself.

The table already had the needed columns:

- `job_name`
- `locked_until`
- `locked_by`
- `updated_at`

The real problem was the runtime behavior:

1. `EventSyncService` and `SnapshotService` were transactional across the whole job
2. `tryAcquire(...)` joined that same transaction
3. lock state was not committed before RPC work
4. acquire logic used read-then-write style instead of one atomic DB statement

So the issue was mainly:

- transaction boundary
- atomicity of lock acquire

---

## 4. What Changed

The fix used three changes together.

### 4-1. Lock acquire is now separately committed

`JobLockService.tryAcquire(...)` now runs in:

```java
@Transactional(propagation = Propagation.REQUIRES_NEW)
```

Meaning:

- lock acquire gets its own transaction
- it commits immediately
- only after that does the outer job continue

So the lock becomes visible to other requests before long RPC work starts.

### 4-2. Lock acquire is now atomic in SQL

Instead of:

- `findById()`
- check expiration in Java
- then `save()`

the code now uses one PostgreSQL upsert statement:

```sql
INSERT INTO job_lock (job_name, locked_until, locked_by, updated_at)
VALUES (:jobName, :lockedUntil, :lockedBy, :now)
ON CONFLICT (job_name) DO UPDATE
  SET locked_until = :lockedUntil,
      locked_by = :lockedBy,
      updated_at = :now
WHERE job_lock.locked_until <= :now
```

This means:

1. if no row exists, insert succeeds
2. if a row exists but the lease is expired, update succeeds
3. if a row exists and the lease is still active, nothing updates

So acquire succeeds only when the lock is free or expired.

### 4-3. Release is owner-aware

Each run now generates a unique lock owner token, currently via UUID.

Release no longer means:

- "unlock by job name only"

It now means:

- "unlock only if this run is still the owner"

So release uses both:

- `job_name`
- `locked_by`

This prevents an older run from releasing a newer run's lock after lease expiry.

---

## 5. Why `locked_by` And UUID Matter

This part is easy to miss.

Imagine:

1. run A acquires lock
2. run A is still working
3. lease expires
4. run B acquires the same lock
5. run A finishes late and tries to release

If release only checks `job_name`, run A could accidentally clear run B's lock.

That is why each run needs its own owner token.

Example:

- run A owner: `uuid-a`
- run B owner: `uuid-b`

Release must update only when:

```sql
where job_name = :jobName
  and locked_by = :lockedBy
```

Then run A cannot release run B's lock.

---

## 6. What "Release" Means In This Design

This codebase uses a lease-based lock.

So release does not delete the row.

Instead, release means:

- set `locked_until = now()`

Why that works:

- `locked_until > now()` means lock is still active
- `locked_until <= now()` means lock is available again

So unlocking is implemented by moving the lease end time to the present.

---

## 7. Files Changed For The Fix

The core R1 fix touched these files:

- `backend/src/main/java/io/forkcast/backend/job/repository/JobLockRepository.java`
- `backend/src/main/java/io/forkcast/backend/job/service/JobLockService.java`
- `backend/src/main/java/io/forkcast/backend/sync/service/EventSyncService.java`
- `backend/src/main/java/io/forkcast/backend/snapshot/service/SnapshotService.java`

Test file added:

- `backend/src/test/java/io/forkcast/backend/job/service/JobLockServiceTest.java`

---

## 8. How The Fix Was Verified

The following tests were added:

1. acquire succeeds once, then fails while lease is still active
2. release with the wrong owner does not unlock
3. release with the correct owner unlocks

Executed command:

```bash
./gradlew test --tests io.forkcast.backend.job.service.JobLockServiceTest
```

Result:

- test passed

---

## 9. What This Fix Does Not Solve

This fix specifically addresses `R1`: unsafe lock commit timing and unsafe lock ownership.

It does not fully solve:

- `job_run` rollback risk (`R3`)
- long snapshot transaction scope (`R4`)
- lease extension for very long-running jobs
- end-to-end overlap testing for full scheduler flows

So this is an important safety fix, but not the end of scheduler hardening work.

---

## 10. Short Summary

The bug was:

- lock acquire existed
- but it was not committed early enough
- and release was not owner-safe

The fix was:

- commit lock acquire in its own transaction
- use one atomic SQL statement for acquire
- release only when `locked_by` still matches the current run

That makes `job_lock` much safer against overlapping scheduler requests.
