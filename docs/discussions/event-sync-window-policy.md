# Event-sync Window Policy Discussion

> Date: 2026-04-30
> Scope: v1 backend event-sync runtime policy

---

## 1. Problem

We needed to decide how v1 `event-sync` should choose its block range.

The main tensions were:

- lower RPC and Cloud Run cost
- simple operational behavior
- avoiding recent-block instability
- keeping frontend query data fresh enough

We also clarified one important responsibility boundary:

- Cloud Scheduler only triggers `POST /internal/jobs/event-sync`
- The backend computes `fromBlock` and `toBlock`

Cloud Scheduler does not decide block numbers.

---

## 2. Reality of the system

Current assumptions used in the discussion:

- Chain: Sepolia
- Approximate block time: 12 seconds
- Scheduler interval under consideration: 5 minutes
- Approximate new blocks per run: about 25
- Backend role: off-chain indexer/query backend, not a transaction executor

This matters because the backend data is mainly:

- event history
- open position read models
- pool price events

This is not the same as a real-time matching engine or wallet receipt tracker.

---

## 3. Options considered

### Option A. Read up to the latest block

Example:

- `fromBlock = lastSyncedBlock + 1`
- `toBlock = latestBlock`

Pros:

- freshest possible data
- easiest for user-visible latency

Cons:

- latest blocks may still change
- more risk of reading unstable data
- creates pressure to handle reorg correction early

Conclusion:

Too aggressive for v1.

---

### Option B. Rewind overlap window

Example:

- `fromBlock = lastSyncedBlock - 4`
- `toBlock = latestBlock - smallLag`

Pros:

- can re-check recent blocks
- more robust against recent block changes

Cons:

- requires recent-range reconciliation
- may require delete/rebuild or orphan handling
- increases implementation complexity
- makes projection logic harder to explain and debug

Conclusion:

Valid later, but too complex for the first version.

---

### Option C. Forward-only sync with safe head

Example:

- `fromBlock = lastSyncedBlock + 1`
- `toBlock = latestBlock - 5`

Pros:

- simple to reason about
- no rewind/rebuild requirement in v1
- safer than reading newest blocks immediately
- easier cursor semantics and debugging

Cons:

- newest events may appear one scheduler cycle later
- data freshness is intentionally lower

Conclusion:

Best fit for current v1 goals.

---

## 4. Scheduler interval discussion

We also discussed whether `event-sync` should start at 1 minute or 5 minutes.

### 1 minute

Pros:

- fresher query data
- shorter wait until event-driven read models update

Cons:

- increases downstream work:
  - Cloud Run executions
  - RPC calls
  - DB writes
- less aligned with the current preference for a conservative first version

### 5 minutes

Pros:

- simpler operations
- lower downstream usage
- easier to explain and monitor

Cons:

- slower user-visible backend updates

Conclusion:

For v1, we chose 5 minutes.

---

## 5. Final v1 decision

We chose the following policy.

### Scheduler responsibility

- Cloud Scheduler runs every 5 minutes
- It only triggers the internal event-sync endpoint

### Backend responsibility

- Read `latestBlock` from RPC
- Compute `safeHead = latestBlock - 5`
- If cursor exists:
  - `fromBlock = lastSyncedBlock + 1`
- Otherwise:
  - `fromBlock = configuredStartBlock`
- Set `toBlock = safeHead`
- If `toBlock < fromBlock`, do no work
- On success, advance cursor to `toBlock`

---

## 6. Why this choice is acceptable

We accepted lower freshness because:

- this backend is an indexer/query backend
- v1 values stable and explainable behavior over aggressive near-real-time sync
- the data being synced is closer to historical/query data than strict immediate wallet UX
- avoiding newest blocks is simpler than adding rewind/rebuild logic now

In practice, a user action included in the newest excluded blocks may appear on the next scheduler run.

That delay is acceptable for v1 event/query data.

---

## 7. What we are intentionally not doing in v1

- no block-range decision in Cloud Scheduler
- no overlap rewind window
- no recent-range rebuild flow
- no dedicated tx receipt watcher

These may be revisited later if product needs or observed sync lag require them.
