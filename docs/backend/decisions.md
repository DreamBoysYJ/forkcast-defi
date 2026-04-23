# Backend Decisions

> This document records key backend design decisions for v1.
> It explains why certain choices were made.

---

## 1. Backend purpose

Decision:

The backend is an off-chain indexer/query backend, not a transaction executor.

Reason:

Users should continue submitting transactions through their wallet.

The backend observes chain events, stores historical data, creates read models, and provides query APIs.

---

## 2. Frontend transaction hints are not final truth

Decision:

Frontend may call `POST /api/tx-hints` after submitting a wallet transaction.

The backend stores this in `pending_tx`.

However, the backend does not treat this as final truth.

Reason:

A frontend-submitted tx can:

- fail
- revert
- stay pending
- be dropped
- be affected by reorg
- be reported incorrectly

Final state should come from on-chain event sync.

---

## 3. Use raw event table plus read models

Decision:

Use:

- `raw_chain_event`
- `position_timeline`
- `pool_price_event`
- `strategy_position`

instead of one table per event type only.

Reason:

Raw events provide replay/debugging capability.

Read models provide query-friendly data for frontend APIs.

This separates:

- ingest source
- projection result
- frontend query model

Benefits:

- Easier reprocessing
- Easier debugging
- More flexible API queries
- Less coupling between raw log shape and UI response shape

Tradeoff:

- Extra projection logic is required.
- Some events may cause two writes:
  - raw event write
  - read model write

This is acceptable for v1.

---

## 4. Store JSON payload in `raw_chain_event`

Decision:

Store decoded event fields in `payload_json`.

Reason:

Event types have different fields.

A single raw event table can store all event types if event-specific fields are placed in JSON.

In PostgreSQL, this should likely be `jsonb`.

This is acceptable for v1 because:

- event volume is low
- payload size is small
- raw table is mainly for replay/debugging
- read models extract frequently queried fields

---

## 5. Store both `tick` and `sqrt_price_x96`

Decision:

Store both values in `pool_price_event`.

Reason:

The hook emits both.

Dropping one early is premature optimization.

Storage cost is negligible in v1.

Keeping both improves future flexibility for:

- charting
- price reconstruction
- debugging
- comparison with contract logs

---

## 6. Store `pool_id`

Decision:

Store `pool_id` in `pool_price_event`.

Reason:

Even if v1 uses one pool, pool identity is part of the event.

Storing it makes the schema future-friendly with minimal cost.

---

## 7. Store both `user_address` and `vault_address`

Decision:

Store both values where they are useful.

Reason:

Although user-vault mapping exists, keeping both in read models improves:

- query simplicity
- debugging
- auditability
- future multi-vault support

Storage overhead is negligible in v1.

---

## 8. User can have multiple vaults

Decision:

`user_vault` uses `id` as PK and `vault_address` as unique.

`user_address` is not unique.

Reason:

A user may have multiple vaults.

The schema should not assume strict 1:1 mapping.

---

## 9. Minimize FK constraints in v1

Decision:

Do not aggressively enforce FK constraints in v1.

Logical relationships are documented, but DB FK constraints are minimized.

Reason:

This backend is an ingest/projection system.

External chain events arrive from an outside source.

Jobs run on different schedules.

Reorg, retry, replay, and backfill flows can make strict insert ordering harder.

FK constraints may make ingestion/reprocessing more fragile.

Recommended:

- Keep raw ingest tables independent.
- Keep operational tables independent.
- Consider FK later for stable read models if needed.

---

## 10. Use unique constraints for duplicate prevention

Decision:

Use unique constraints where duplicate prevention is required.

Important unique rules:

- `pending_tx.tx_hash`
- `raw_chain_event(tx_hash, log_index)`
- `pool_price_event(tx_hash, log_index)`
- `user_vault.vault_address`
- `position_snapshot(token_id, snapshot_at)`

Reason:

Retry-safe processing depends on idempotent writes.

If the same block range is processed again, duplicates should be ignored or safely upserted.

---

## 11. Use Cloud Scheduler instead of in-process scheduler

Decision:

Production recurring jobs are triggered by Cloud Scheduler.

Reason:

Cloud Run can scale to zero.

Cloud Run can also scale out to multiple instances.

An in-process scheduler can fail to run or run multiple times.

Cloud Scheduler calling internal endpoints gives clearer runtime behavior.

---

## 12. Use job locks

Decision:

Use `job_lock` with `locked_until`.

Reason:

Cloud Scheduler can retry or duplicate calls.

Manual calls can also happen.

Multiple Cloud Run instances may exist.

The same job should not run concurrently.

A lease-based lock is safer than a boolean lock.

---

## 13. Event-sync interval starts at 1 minute

Decision:

Initial `event-sync` interval is 1 minute.

Reason:

Event sync affects user-visible history and open position lists.

Too much delay creates poor UX.

Cloud Scheduler is naturally minute-based.

The queried event scope is narrow:

- Router events
- Hook events

This is a practical v1 starting point.

---

## 14. Snapshot interval starts at 5 minutes

Decision:

Initial `snapshot` interval is 5 minutes.

Reason:

Snapshots are current-state history, not immediate position existence.

Position existence is updated through event-sync.

Snapshot calls may become heavier as open position count grows.

Too frequent snapshots may create many nearly identical rows.

5 minutes is a reasonable v1 balance.

---

## 15. Position existence and snapshot are separate

Decision:

A newly opened position should appear through `strategy_position`, not wait for snapshot.

Reason:

Users expect open positions to appear quickly.

`strategy_position` is updated by event-sync from `PositionOpened`.

`position_snapshot` enriches known positions with deeper state later.

---

## 16. API spec is draft-first

Decision:

API request/response examples are written as draft examples first.

Reason:

The API shape may change during implementation.

Early examples help with thinking, frontend planning, and QA planning.

Final contract can later be stabilized through DTOs and OpenAPI/Swagger.
