# Backend Goal

## One-sentence goal

Forkcast DeFi 백엔드의 목표는 블록체인에서 발생하는 이벤트 히스토리와 포지션 상태 스냅샷을 reorg, retry safe하게 DB에 저장하고, 이를 조회 가능한 형태로 제공하는 것이다.

## Why this backend exists

Forkcast DeFi currently has smart contracts and a frontend.

The backend is added to solve problems that are difficult to handle with only frontend/on-chain reads:

- Historical event lookup
- Position lifecycle history
- Pool price event history
- Current open position query
- Periodic position state snapshots
- Sync/retry/reorg-aware processing
- Operational visibility

## What this backend is not

This backend is not:

- A wallet transaction signer
- A replacement for user wallet interaction
- A simple REST wrapper around blockchain calls
- A centralized execution layer for user actions
- A full production-grade DeFi analytics system in v1

Users still submit transactions through their wallet.

The backend observes and indexes what happened on-chain.

## v1 scope

The v1 backend should support:

1. Receiving frontend tx hints
2. Syncing Router and Hook events from chain logs
3. Storing raw chain events
4. Building read models from events
5. Storing current position metadata
6. Storing periodic position snapshots
7. Providing query APIs for frontend
8. Running scheduled jobs safely
9. Tracking job/cursor state

## Out of scope for v1

The following are intentionally out of scope for v1:

- Perfect real-time sync
- Full PnL accuracy
- Complex analytics dashboard
- Multi-chain support
- Kafka/event streaming infrastructure
- Elasticsearch/OpenSearch
- Advanced alerting system
- Full admin console
- Contract redesign

## Key backend design ideas

### 1. Frontend tx hints are not final truth

Frontend can notify backend after submitting a transaction.

Example:
- txHash
- actionType
- userAddress

But this only means:

> The user attempted something.

The final truth comes from on-chain events.

### 2. Event sync is the source of historical truth

The backend periodically reads blockchain logs and stores:

- `PositionOpened`
- `PositionClosed`
- `FeesCollected`
- `SwapPriceLogged`

### 3. Snapshot is current-state history

Events explain what happened.

Snapshots explain what the position looked like at a point in time.

### 4. Raw event and read model are separated

Raw events are stored for replay/debugging.

Read models are created for API/query convenience.

### 5. Operational state is first-class

The backend must store:

- sync cursor
- job lock
- job run history

This is required for retry-safe scheduled jobs.
