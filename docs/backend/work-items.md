# Backend Work Items (Draft)

> This document breaks backend implementation into small tasks.
> It should be updated as the project moves from planning to coding.

---

## Phase 0. Planning freeze

### 0-1. Confirm planning docs

Inputs:
- `docs/backend/goal.md`
- `docs/backend/data-model.md`
- `docs/backend/api-spec.md`
- `docs/backend/scheduler-plan.md`
- `docs/backend/decisions.md`

Output:
- Planning docs are consistent enough to start implementation.

Done when:
- Data model is accepted.
- API draft is accepted.
- Scheduler plan is accepted.
- Major decisions are documented.

---

## Phase 1. Backend project setup

### 1-1. Create Spring Boot backend module

Output:
- Backend app skeleton

Expected stack:
- Java 21
- Spring Boot
- Spring Web
- Spring Data JPA
- PostgreSQL driver
- Flyway
- Actuator

Done when:
- App starts locally.
- Health endpoint works.
- Basic package structure exists.

---

### 1-2. Configure local database

Output:
- Local PostgreSQL setup
- dev profile config

Done when:
- Backend can connect to local PostgreSQL.
- Flyway can run migrations.

---

## Phase 2. Database schema

### 2-1. Write initial Flyway migration

Create tables:

- `sync_cursor`
- `job_lock`
- `job_run`
- `pending_tx`
- `raw_chain_event`
- `strategy_position`
- `position_timeline`
- `pool_price_event`
- `position_snapshot`
- `user_vault`

Done when:
- Migration runs successfully.
- Unique constraints are applied.
- Timestamp columns are present.

---

### 2-2. Create JPA entities/repositories

Priority:
1. Operational tables
2. Pending tx
3. Event/read model tables
4. Snapshot tables

Done when:
- Basic repository tests pass.
- Unique constraint violations are understood/handled.

---

## Phase 3. Internal job infrastructure

### 3-1. Implement job lock service

Uses:
- `job_lock`

Done when:
- Lock can be acquired.
- Lock is skipped when already held.
- Expired lock can be acquired again.
- Lock is released after execution.

---

### 3-2. Implement job run logging

Uses:
- `job_run`

Done when:
- Successful job run is logged.
- Failed job run is logged.
- Error message is stored.

---

## Phase 4. Event sync

### 4-1. Implement chain log client skeleton

Purpose:
- Fetch logs from RPC using address/topic/block range.

Done when:
- The service can request logs for a block range.
- RPC configuration is externalized.

---

### 4-2. Implement event decoding

Events:
- `PositionOpened`
- `PositionClosed`
- `FeesCollected`
- `SwapPriceLogged`

Done when:
- Decoded event objects can be created from logs.

---

### 4-3. Store raw chain events

Uses:
- `raw_chain_event`

Done when:
- Logs are inserted idempotently.
- Duplicate `(tx_hash, log_index)` is handled safely.

---

### 4-4. Project raw events into read models

Read models:
- `strategy_position`
- `position_timeline`
- `pool_price_event`
- `user_vault`

Done when:
- `PositionOpened` creates/updates `strategy_position`.
- `PositionOpened` creates timeline event.
- `PositionClosed` updates `strategy_position`.
- `FeesCollected` creates timeline event.
- `SwapPriceLogged` creates pool price event.

---

### 4-5. Implement event-sync endpoint

Endpoint:
- `POST /internal/jobs/event-sync`

Done when:
- Endpoint is protected.
- Job lock is used.
- Cursor is updated only after success.
- Job run is logged.
- Duplicate calls are safely skipped.

---

## Phase 5. Snapshot

### 5-1. Implement lens client skeleton

Purpose:
- Call StrategyLens or view function for position state.

Done when:
- Given tokenId, backend can read current state.

---

### 5-2. Implement snapshot service

Uses:
- `strategy_position`
- `position_snapshot`

Done when:
- Open positions are selected.
- Current state is read.
- Snapshot row is inserted with `snapshot_at`.

---

### 5-3. Implement snapshot endpoint

Endpoint:
- `POST /internal/jobs/snapshot`

Done when:
- Endpoint is protected.
- Job lock is used.
- Job run is logged.
- Duplicate execution is skipped.

---

## Phase 6. Public API

### 6-1. Implement pool price event API

Endpoint:
- `GET /api/pools/{poolId}/price-events`

Done when:
- Returns paginated price events.
- Validates poolId.

---

### 6-2. Implement user open positions API

Endpoint:
- `GET /api/users/{userAddress}/positions/open`

Done when:
- Returns open positions for one user.
- Supports limit/cursor.

---

### 6-3. Implement all open positions API

Endpoint:
- `GET /api/positions/open`

Done when:
- Returns global open positions.
- Supports optional owner/vault filters.

---

### 6-4. Implement position timeline API

Endpoint:
- `GET /api/positions/{tokenId}/timeline`

Done when:
- Returns lifecycle events in time order.
- Supports pagination.

---

### 6-5. Implement tx hint API

Endpoint:
- `POST /api/tx-hints`

Done when:
- Stores tx hint.
- Enforces unique txHash.
- Does not create final strategy position directly.

---

## Phase 7. Tests

### 7-1. Repository tests

Covers:
- unique constraints
- inserts
- updates
- idempotent writes

---

### 7-2. Job lock tests

Covers:
- acquire
- skip
- expired lock recovery
- release

---

### 7-3. Event projection tests

Covers:
- PositionOpened
- PositionClosed
- FeesCollected
- SwapPriceLogged

---

### 7-4. API tests

Covers:
- success responses
- invalid request
- not found cases
- duplicate tx hint

---

## Phase 8. Deployment preparation

### 8-1. Dockerfile

Done when:
- Backend can be built and run as container.

---

### 8-2. Cloud Run environment config

Done when:
- Required env variables are documented.

---

### 8-3. Cloud Scheduler setup

Jobs:
- event-sync
- snapshot

Done when:
- Scheduler can invoke internal endpoints safely.
