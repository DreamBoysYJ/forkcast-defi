# API Spec

> 이 문서는 v1 백엔드 API 문서다.
> 외부 조회 API의 JSON 예시는 2026-05-01 기준 실제 로컬 실행 응답을 반영했다.
> 외부 조회 API는 백엔드 DB 기준 데이터이며, 체인 최신 상태와 즉시 100% 일치하지 않을 수 있다.

---

## 목차

1. [외부 조회 API](#1-외부-조회-api)
   - [1-1. 특정 풀의 가격 이벤트 히스토리 조회](#1-1-특정-풀의-가격-이벤트-히스토리-조회)
   - [1-2. 내 현재 오픈 포지션 목록 조회](#1-2-내-현재-오픈-포지션-목록-조회)
   - [1-3. 현재 활성화된 전체 포지션 목록 조회](#1-3-현재-활성화된-전체-포지션-목록-조회)
   - [1-4. 특정 포지션의 활동 타임라인 조회](#1-4-특정-포지션의-활동-타임라인-조회)
   - [1-5. 특정 포지션의 상태 스냅샷 조회](#1-5-특정-포지션의-상태-스냅샷-조회)
   - [1-6. 트랜잭션 힌트 저장](#1-6-트랜잭션-힌트-저장)
2. [내부 운영 API](#2-내부-운영-api)
   - [2-1. 이벤트 동기화 job 실행](#2-1-이벤트-동기화-job-실행)
   - [2-2. 스냅샷 job 실행](#2-2-스냅샷-job-실행)
3. [추후 추가 가능성이 높은 API](#3-추후-추가-가능성이-높은-api)

---

## 1. 외부 조회 API

### 1-1. 특정 풀의 가격 이벤트 히스토리 조회

**`GET`** `/api/pools/{poolId}/price-events`

**목적**
특정 풀에서 발생한 가격 이벤트(`tick`, `sqrtPriceX96`) 이력을 시간순으로 조회한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Path | `poolId` | string | 필수 |
| Query | `limit` | number | 선택 |

#### Response `200`

```json
{
  "items": [
    {
      "poolId": "0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c",
      "tick": 181,
      "sqrtPriceX96": "79952138169375659744523659895",
      "eventTimestamp": "2026-04-30T13:22:31.510890Z",
      "txHash": "0xc21d0d3a736f929f4502b305b478a4aa72dce58a3980b8e51b44f46cfe94dac9",
      "blockNumber": 10762272
    },
    {
      "poolId": "0x26ac4021c01554ab2610eb42ffb59c9b862b592d6426b04b103fcb26f180c72c",
      "tick": 615,
      "sqrtPriceX96": "81704584234007579983257865353",
      "eventTimestamp": "2026-04-30T13:22:31.508917Z",
      "txHash": "0x49dd63d6a7d871e52818b13d4e4981c824c1ac5deeabc1cd292ae00e20e24c44",
      "blockNumber": 10761011
    }
  ],
  "nextCursor": null
}
```

#### Notes

- `pool_price_event` 기반 조회
- on-chain hook 이벤트를 백엔드가 수집한 결과를 반환
- 완전 실시간이 아닐 수 있음
- 현재는 pagination을 쓰지 않아서 `nextCursor`는 항상 `null`
- v1 조회 정책상 결과가 없으면 `404` 대신 `200` + empty `items`를 반환할 수 있다

---

### 1-2. 내 현재 오픈 포지션 목록 조회

**`GET`** `/api/users/{userAddress}/positions/open`

**목적**
특정 유저가 현재 보유한 오픈 포지션 목록을 조회한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Path | `userAddress` | string | 필수 |
| Query | `limit` | number | 선택 |

#### Response `200`

```json
{
  "items": [
    {
      "tokenId": 20891,
      "ownerAddress": "0x7a227d5902ca52c0c3c61304533bff4632fce145",
      "vaultAddress": "0x7eeb6ac4cdbc7f52d82ffa232f93ee170b6d1596",
      "supplyAsset": "0x88541670e55cc00beefd87eb59edd1b7c511ac9a",
      "borrowAsset": "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5",
      "isOpen": true,
      "openedBlock": 9715930,
      "openedTxHash": "0x091eef14dadc6f4ac432c153ab0b3b8bfdc93a538511d31a3eed18745a1f1dfe"
    }
  ],
  "nextCursor": null
}
```

#### Notes

- `strategy_position` 기반 조회
- 포지션별 상세 상태는 별도 API에서 조회
- 현재는 pagination을 쓰지 않아서 `nextCursor`는 항상 `null`
- v1 조회 정책상 결과가 없으면 `404` 대신 `200` + empty `items`를 반환할 수 있다

---

### 1-3. 현재 활성화된 전체 포지션 목록 조회

**`GET`** `/api/positions/open`

**목적**
현재 활성화된 전체 오픈 포지션 목록을 조회한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Query | `limit` | number | 선택 |

#### Response `200`

```json
{
  "items": [
    {
      "tokenId": 20891,
      "ownerAddress": "0x7a227d5902ca52c0c3c61304533bff4632fce145",
      "vaultAddress": "0x7eeb6ac4cdbc7f52d82ffa232f93ee170b6d1596",
      "supplyAsset": "0x88541670e55cc00beefd87eb59edd1b7c511ac9a",
      "borrowAsset": "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5",
      "isOpen": true,
      "openedBlock": 9715930,
      "openedTxHash": "0x091eef14dadc6f4ac432c153ab0b3b8bfdc93a538511d31a3eed18745a1f1dfe"
    }
  ],
  "nextCursor": null
}
```

#### Error

| 코드 | 설명 |
|------|------|
| `400` | invalid query parameter |
| `500` | internal error |

#### Notes

- `strategy_position` 기반 조회
- 전체 활동/운영 대시보드용 목록 API
- 현재 구현은 `limit`만 지원한다
- 현재는 pagination을 쓰지 않아서 `nextCursor`는 항상 `null`

---

### 1-4. 특정 포지션의 활동 타임라인 조회

**`GET`** `/api/positions/{tokenId}/timeline`

**목적**
특정 포지션이 지금까지 겪은 이벤트 이력을 시간순으로 조회한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Path | `tokenId` | number | 필수 |
| Query | `limit` | number | 선택 |

#### Response `200`

```json
{
  "items": [
    {
      "tokenId": 20891,
      "eventType": "OPENED",
      "txHash": "0x091eef14dadc6f4ac432c153ab0b3b8bfdc93a538511d31a3eed18745a1f1dfe",
      "blockNumber": 9715930,
      "eventTimestamp": "2026-04-30T13:22:31.390017Z",
      "userAddress": "0x7a227d5902ca52c0c3c61304533bff4632fce145",
      "vaultAddress": "0x7eeb6ac4cdbc7f52d82ffa232f93ee170b6d1596",
      "metadata": "{\"spent0\": \"23416208119247950375\", \"spent1\": \"24074074074000000000\", \"borrowAsset\": \"0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5\", \"supplyAsset\": \"0x88541670e55cc00beefd87eb59edd1b7c511ac9a\", \"amount0ForLp\": \"23502676894297692363\", \"amount1ForLp\": \"24074074074000000000\", \"supplyAmount\": \"10000000000000000000\", \"borrowedAmount\": \"48148148148000000000\"}"
    }
  ],
  "nextCursor": null
}
```

#### Notes

- `position_timeline` 기반 조회
- 포지션 하나의 lifecycle 이벤트 이력 제공
- 현재 `metadata`는 nested object가 아니라 JSON string으로 내려온다
- 현재는 pagination을 쓰지 않아서 `nextCursor`는 항상 `null`
- v1 조회 정책상 결과가 없으면 `404` 대신 `200` + empty `items`를 반환할 수 있다

---

### 1-5. 특정 포지션의 상태 스냅샷 조회

**`GET`** `/api/positions/{tokenId}/snapshots`

**목적**
특정 포지션의 주기적 상태 스냅샷 히스토리를 최신순으로 조회한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Path | `tokenId` | number | 필수 |
| Query | `limit` | number | 선택 |

#### Response `200`

```json
{
  "items": [
    {
      "tokenId": 990001,
      "ownerAddress": "0x9cf7b6b56c9bc0ab6c0c0d60db8c8b5fa67c5f6e",
      "vaultAddress": "0x1234567890abcdef1234567890abcdef12345678",
      "supplyAsset": "0x88541670e55cc00beefd87eb59edd1b7c511ac9a",
      "borrowAsset": "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5",
      "isOpen": true,
      "liquidity": "125000000000000000",
      "amount0Now": "23416208119247950375",
      "amount1Now": "24074074074000000000",
      "currentTick": 181,
      "sqrtPriceX96": "79952138169375659744523659895",
      "totalCollateralBase": "100456789",
      "totalDebtBase": "50456789",
      "healthFactor": "1.987654321000000000",
      "snapshotAt": "2026-05-01T07:15:00Z",
      "observedBlockNumber": 10762310
    }
  ],
  "nextCursor": null
}
```

#### Notes

- `position_snapshot` 기반 조회
- snapshot은 이벤트 히스토리가 아니라 특정 시점의 상태 히스토리다
- bigint / decimal 계열 값은 정밀도 보존을 위해 string으로 내려온다
- debt가 0인 포지션에서 컨트랙트가 sentinel max 값을 돌려주는 경우, `healthFactor`는 저장 가능한 최대 finite 값으로 요약될 수 있다
- 현재는 pagination을 쓰지 않아서 `nextCursor`는 항상 `null`
- v1 조회 정책상 결과가 없으면 `404` 대신 `200` + empty `items`를 반환할 수 있다

---

### 1-6. 트랜잭션 힌트 저장

**`POST`** `/api/tx-hints`

**목적**
프론트가 트랜잭션 제출 직후 `txHash`와 액션 정보를 백엔드에 전달하여 pending 상태를 기록한다.

#### Request

| 위치 | 파라미터 | 타입 | 필수 여부 |
|------|----------|------|-----------|
| Body | `txHash` | string | 필수 |
| Body | `actionType` | string | 필수 |
| Body | `userAddress` | string | 필수 |

#### Request Body 예시

```json
{
  "txHash": "0xabc123",
  "actionType": "OPEN_POSITION",
  "userAddress": "0xUser1"
}
```

#### Response `202`

```json
{
  "status": "ACCEPTED",
  "txHash": "0xabc123"
}
```

#### Error

| 코드 | 설명 |
|------|------|
| `400` | invalid request body |
| `400` | duplicate txHash |
| `500` | internal error |

#### Notes

- `pending_tx` 저장용
- 최종 포지션 생성/확정은 하지 않음
- 최종 상태 반영은 on-chain event-sync 결과 기준

---

## 2. 내부 운영 API

> 아래 API는 외부 공개용이 아니다. Cloud Scheduler 또는 내부 운영 경로에서만 호출한다.

### 2-1. 이벤트 동기화 job 실행

**`POST`** `/internal/jobs/event-sync`

**목적**
Router / Hook 이벤트를 체인에서 읽고 DB에 반영한다.

#### Request

| 위치 | 파라미터 | 설명 |
|------|----------|------|
| Header | `Authorization` | `Bearer <OIDC ID token>` |
| Body | — | 없음 |

#### Response `200`

```json
{
  "jobName": "event-sync",
  "status": "SUCCESS",
  "rangeStartBlock": 123401,
  "rangeEndBlock": 123460,
  "processedEvents": 14,
  "updatedCursor": 123460,
  "startedAt": "2026-04-18T10:00:00Z",
  "finishedAt": "2026-04-18T10:00:03Z"
}
```

#### Response `202` (이미 실행 중인 경우)

```json
{
  "jobName": "event-sync",
  "status": "SKIPPED",
  "reason": "already running"
}
```

#### Error

| 코드 | 설명 |
|------|------|
| `401` | unauthorized |
| `403` | forbidden |
| `500` | internal error |

#### Notes

- `job_lock`, `sync_cursor`, `job_run` 사용
- raw event 저장 및 read model 반영 수행
- Cloud Scheduler 전용 service account의 OIDC 토큰만 허용하는 방향으로 운영

---

### 2-2. 스냅샷 job 실행

**`POST`** `/internal/jobs/snapshot`

**목적**
현재 오픈 포지션 상태를 조회하고 snapshot을 저장한다.

#### Request

| 위치 | 파라미터 | 설명 |
|------|----------|------|
| Header | `Authorization` | `Bearer <OIDC ID token>` |
| Body | — | 없음 |

#### Response `200`

```json
{
  "jobName": "snapshot",
  "status": "SUCCESS",
  "snapshottedPositions": 8,
  "startedAt": "2026-04-18T10:05:00Z",
  "finishedAt": "2026-04-18T10:05:04Z"
}
```

#### Response `202` (이미 실행 중인 경우)

```json
{
  "jobName": "snapshot",
  "status": "SKIPPED",
  "reason": "already running"
}
```

#### Error

| 코드 | 설명 |
|------|------|
| `401` | unauthorized |
| `403` | forbidden |
| `500` | internal error |

#### Notes

- `StrategyLens` 기반 상태 조회
- `position_snapshot` 저장
- event-sync보다 느린 주기로 실행 가능
- Cloud Scheduler 전용 service account의 OIDC 토큰만 허용하는 방향으로 운영

---

## 3. 추후 추가 가능성이 높은 API

아래는 v1 이후 추가될 수 있는 후보들이다.

| 엔드포인트 | 설명 |
|-----------|------|
| `GET /api/positions/{tokenId}` | 특정 포지션 상세 조회 |
| `GET /api/system/sync-status` | 운영 상태 확인 |
| `GET /api/users/{userAddress}/vaults` | 유저의 vault 목록 조회 |
