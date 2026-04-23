# Backend Test Scenarios (Draft)

> This document defines v1 test scenarios.
> It is not test code yet.
> It is used to guide implementation and QA.

---

## 1. Pending tx scenarios

### 1-1. Submit valid tx hint

Given:
- frontend sends txHash, actionType, userAddress

When:
- `POST /api/tx-hints` is called

Then:
- row is inserted into `pending_tx`
- status is `PENDING`
- response is `202 ACCEPTED`

---

### 1-2. Submit duplicate tx hint

Given:
- `pending_tx` already has same txHash

When:
- same txHash is submitted again

Then:
- backend should not create duplicate row
- response should be either idempotent success or `409`
- chosen behavior must be documented

---

### 1-3. Invalid tx hint body

Given:
- missing txHash or invalid userAddress

When:
- API is called

Then:
- response is `400`

---

## 2. Event-sync scenarios

### 2-1. Successful event sync

Given:
- sync cursor exists
- RPC returns Router and Hook logs

When:
- `POST /internal/jobs/event-sync` is called

Then:
- raw events are inserted
- read models are updated
- cursor advances
- job_run is recorded as success

---

### 2-2. Event-sync duplicate retry

Given:
- same block range is processed twice

When:
- event-sync runs again

Then:
- duplicate raw events are not inserted
- duplicate pool price events are not inserted
- timeline/position projection remains consistent

---

### 2-3. RPC failure during event-sync

Given:
- RPC fails during log fetch

When:
- event-sync runs

Then:
- job_run is recorded as failed
- cursor should not advance past failed range
- lock should be released or expire safely

---

### 2-4. Partial processing failure

Given:
- some logs were fetched
- DB failure happens before cursor update

When:
- job is retried

Then:
- unique constraints prevent duplicates
- processing can continue safely

---

## 3. Job lock scenarios

### 3-1. Acquire free lock

Given:
- no active lock exists

When:
- job starts

Then:
- lock is acquired
- job runs

---

### 3-2. Skip already running job

Given:
- `locked_until` is in the future

When:
- same job endpoint is called again

Then:
- job does not run
- response is `202 SKIPPED`

---

### 3-3. Recover expired lock

Given:
- previous job died
- `locked_until` is in the past

When:
- job starts again

Then:
- new job can acquire lock

---

## 4. Projection scenarios

### 4-1. Project PositionOpened

Given:
- raw event `PositionOpened`

When:
- projection runs

Then:
- `strategy_position` is created or updated
- `position_timeline` receives `OPENED`
- `user_vault` is updated if needed

---

### 4-2. Project PositionClosed

Given:
- raw event `PositionClosed`

When:
- projection runs

Then:
- `strategy_position.is_open` becomes false
- closed block/tx are stored
- `position_timeline` receives `CLOSED`

---

### 4-3. Project FeesCollected

Given:
- raw event `FeesCollected`

When:
- projection runs

Then:
- `position_timeline` receives `FEES_COLLECTED`

---

### 4-4. Project SwapPriceLogged

Given:
- raw event `SwapPriceLogged`

When:
- projection runs

Then:
- `pool_price_event` is inserted

---

## 5. Snapshot scenarios

### 5-1. Successful snapshot

Given:
- there are open positions

When:
- `POST /internal/jobs/snapshot` is called

Then:
- backend calls lens/view function
- `position_snapshot` row is inserted for each open position
- job_run is recorded as success

---

### 5-2. No open positions

Given:
- no strategy_position has `is_open = true`

When:
- snapshot job runs

Then:
- no snapshot rows are inserted
- job_run is still recorded as success

---

### 5-3. Lens/RPC failure

Given:
- lens call fails for one or more positions

When:
- snapshot job runs

Then:
- failure is logged
- behavior should be decided:
  - fail entire job
  - or skip failed position and continue

Recommended v1:
- fail entire job unless partial-snapshot behavior is explicitly implemented

---

## 6. Public API scenarios

### 6-1. Price events list

Endpoint:
- `GET /api/pools/{poolId}/price-events`

Cases:
- valid poolId returns events
- invalid poolId returns 400
- no events returns empty list

---

### 6-2. User open positions

Endpoint:
- `GET /api/users/{userAddress}/positions/open`

Cases:
- valid user returns open positions
- invalid userAddress returns 400
- user with no open positions returns empty list

---

### 6-3. All open positions

Endpoint:
- `GET /api/positions/open`

Cases:
- returns all open positions
- supports optional ownerAddress filter
- supports optional vaultAddress filter

---

### 6-4. Position timeline

Endpoint:
- `GET /api/positions/{tokenId}/timeline`

Cases:
- valid tokenId returns timeline
- invalid tokenId returns 400
- unknown tokenId returns 404 or empty list depending on decision

Recommended v1:
- unknown tokenId returns 404 if strategy_position is missing

---

## 7. Security scenarios

### 7-1. Internal job endpoint unauthorized

Endpoints:
- `POST /internal/jobs/event-sync`
- `POST /internal/jobs/snapshot`

Given:
- request has no valid internal auth

Then:
- response is `401` or `403`

---

### 7-2. Internal job endpoint authorized

Given:
- request comes from Cloud Scheduler / valid auth

Then:
- job can execute

---

## 8. Reorg/retry awareness scenarios

### 8-1. Same block range re-read

Given:
- event-sync re-reads recent block range

Then:
- duplicate raw events are ignored/upserted
- read models stay consistent

---

### 8-2. Removed event handling

Given:
- log has `removed = true`

Then:
- raw event should preserve removed status
- projection behavior must be explicitly decided

Recommended v1:
- finalized-only sync preferred
- removed handling can be minimized if finalized-only is used
