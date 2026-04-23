# Data Model Draft

> This document describes the v1 backend data model.
> It is a planning document, not final SQL DDL.
> API response structures and implementation details may change during development.

---

## 1. Design overview

The backend stores data in five logical groups.

1. Operational tables
2. Frontend tx hint table
3. Raw chain event table
4. Read model tables
5. Snapshot table
6. User-vault mapping table

The backend intentionally separates:

- raw chain events
- projected read models
- periodic snapshots
- operational job metadata

---

## 2. Operational tables

### 2-1. `sync_cursor`

Purpose:

Stores where event sync has processed up to.

| Item | Value |
| --- | --- |
| PK | `cursor_name` |
| Unique | PK itself |
| Needs `id`? | No |
| Main columns | `cursor_name`, `last_synced_block`, `updated_at` |

Example row:

| cursor_name | last_synced_block | updated_at |
| --- | --- | --- |
| `event-sync-finalized` | `1234567` | `2026-04-18T10:00:00Z` |

Notes:

- This table stores current cursor state.
- It should usually have one row per cursor.
- Historical job execution logs are stored in `job_run`.

---

### 2-2. `job_lock`

Purpose:

Prevents the same job from running concurrently.

| Item | Value |
| --- | --- |
| PK | `job_name` |
| Unique | PK itself |
| Needs `id`? | No |
| Main columns | `job_name`, `locked_until`, `locked_by`, `updated_at` |

Example rows:

| job_name | locked_until | locked_by |
| --- | --- | --- |
| `event-sync` | `2026-04-18T10:01:00Z` | `cloud-run-instance-1` |
| `snapshot` | `2026-04-18T10:06:00Z` | `cloud-run-instance-2` |

Notes:

- Do not use only `is_locked boolean`.
- Use a lease-based lock with `locked_until`.
- If the server dies, the lock can expire automatically.

---

### 2-3. `job_run`

Purpose:

Stores job execution history.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | None |
| Needs `id`? | Yes |
| Main columns | `id`, `job_name`, `started_at`, `finished_at`, `status`, `error_message`, `range_start_block`, `range_end_block` |

Notes:

- `sync_cursor` answers: "Where are we now?"
- `job_run` answers: "What happened during each run?"
- Useful for debugging, observability, and failure investigation.

---

## 3. Frontend hint table

### 3-1. `pending_tx`

Purpose:

Stores transaction hints sent from frontend after wallet transaction submission.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | `tx_hash` |
| Needs `id`? | Yes |
| Main columns | `id`, `tx_hash`, `action_type`, `user_address`, `status`, `submitted_at` |

Possible statuses:

- `PENDING`
- `MINED_UNCONFIRMED`
- `CONFIRMED`
- `FAILED`
- `EXPIRED`

Notes:

- This is not final truth.
- This table supports pending UX and later reconciliation.
- Final state should be based on actual on-chain events.

---

## 4. Raw chain event table

### 4-1. `raw_chain_event`

Purpose:

Stores raw blockchain events read from logs.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | `(tx_hash, log_index)` |
| Needs `id`? | Yes |
| Main columns | `id`, `event_name`, `tx_hash`, `block_number`, `block_hash`, `log_index`, `contract_address`, `payload_json`, `event_timestamp`, `removed` |

Stored event types:

- `PositionOpened`
- `PositionClosed`
- `FeesCollected`
- `SwapPriceLogged`

Notes:

- This is the raw source for event history.
- `payload_json` stores event-specific decoded fields.
- `(tx_hash, log_index)` prevents duplicate insertion during retry.
- `contract_address` is stored here because this is the original event source.
- Read models can be rebuilt from this table if projection logic changes.

---

## 5. Read model tables

### 5-1. `strategy_position`

Purpose:

Stores the current basic metadata of a strategy position.

| Item | Value |
| --- | --- |
| PK | `token_id` |
| Unique | PK itself |
| Needs `id`? | No |
| Main columns | `token_id`, `owner_address`, `vault_address`, `supply_asset`, `borrow_asset`, `is_open`, `opened_block`, `closed_block`, `opened_tx_hash`, `closed_tx_hash` |

Notes:

- This is a thin current-state table.
- Created/updated by Router events.
- Used for open position list queries.
- It is lighter than `position_snapshot`.

---

### 5-2. `position_timeline`

Purpose:

Stores position lifecycle events in query-friendly form.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | None in v1 |
| Needs `id`? | Yes |
| Main columns | `id`, `token_id`, `event_type`, `tx_hash`, `block_number`, `event_timestamp`, `user_address`, `vault_address`, `metadata_json` |

Possible event types:

- `OPENED`
- `FEES_COLLECTED`
- `CLOSED`

Notes:

- Built from Router events.
- Supports "my position history".
- Supports global activity feed.
- `metadata_json` stores event-specific details.

---

### 5-3. `pool_price_event`

Purpose:

Stores Hook price events in query-friendly form.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | `(tx_hash, log_index)` |
| Needs `id`? | Yes |
| Main columns | `id`, `pool_id`, `tx_hash`, `block_number`, `log_index`, `tick`, `sqrt_price_x96`, `event_timestamp` |

Notes:

- Built from `SwapPriceLogged`.
- Used for pool price event history and charts.
- `pool_id` is stored even if v1 uses one pool.
- Both `tick` and `sqrt_price_x96` are stored in v1.

---

## 6. Snapshot table

### 6-1. `position_snapshot`

Purpose:

Stores periodic current-state snapshots of open positions.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | `(token_id, snapshot_at)` |
| Needs `id`? | Yes |
| Main columns | `id`, `token_id`, `owner_address`, `vault_address`, `supply_asset`, `borrow_asset`, `is_open`, `liquidity`, `amount0_now`, `amount1_now`, `current_tick`, `sqrt_price_x96`, `total_collateral_base`, `total_debt_base`, `health_factor`, `snapshot_at`, `observed_block_number` |

Notes:

- This is not an event copy.
- This is a point-in-time state photo.
- Based on `StrategyLens` or view calls.
- Must include `snapshot_at`.
- `observed_block_number` helps explain which chain state was observed.

---

## 7. User-vault mapping table

### 7-1. `user_vault`

Purpose:

Stores user-to-vault mapping.

| Item | Value |
| --- | --- |
| PK | `id` |
| Unique | `vault_address` |
| Needs `id`? | Yes |
| Main columns | `id`, `user_address`, `vault_address`, `created_at` |

Notes:

- A user may have multiple vaults.
- Therefore `user_address` is not unique.
- `vault_address` should be unique.
- Useful for querying all vaults owned by a user.

---

## 8. Logical relationships

FK constraints are not mandatory in v1.

However, logical relationships exist.

### Main logical relationships

- `user_vault.vault_address` -> `strategy_position.vault_address`
- `strategy_position.token_id` -> `position_timeline.token_id`
- `strategy_position.token_id` -> `position_snapshot.token_id`

### Raw/projection relationship

- `raw_chain_event` is the ingest source.
- `position_timeline`, `pool_price_event`, and `strategy_position` are projections/read models.
- These relationships are logical processing relationships, not necessarily FK constraints.

---

## 9. FK decision

For v1, FK constraints are minimized.

Reason:

- Blockchain ingest is external-source-driven.
- Event sync and snapshot jobs may run at different times.
- Reorg/retry/replay can require flexible reprocessing.
- Raw events should remain independently storable.
- Insert ordering should not make ingestion fragile.

Recommended:

- Do not add FK to `raw_chain_event`.
- Do not add FK to operational tables.
- Consider FK later only if projection ordering and replay policy become stable.

---

## 10. Final v1 table list

1. `sync_cursor`
2. `job_lock`
3. `job_run`
4. `pending_tx`
5. `raw_chain_event`
6. `strategy_position`
7. `position_timeline`
8. `pool_price_event`
9. `position_snapshot`
10. `user_vault`
