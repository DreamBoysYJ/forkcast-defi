const BACKEND_URL =
  process.env.NEXT_PUBLIC_BACKEND_URL ?? "http://localhost:8080";

export type PriceEventItem = {
  poolId: string;
  tick: number;
  sqrtPriceX96: string;
  eventTimestamp: string;
  txHash: string;
  blockNumber: number;
};

type PriceEventsResponse = {
  items: PriceEventItem[];
  nextCursor: string | null;
};

export async function fetchPriceEvents(
  poolId: string,
  limit = 20
): Promise<PriceEventItem[]> {
  const url = `${BACKEND_URL}/api/pools/${encodeURIComponent(poolId)}/price-events?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`price-events ${res.status}`);
  const data: PriceEventsResponse = await res.json();
  return data.items;
}

// ── User positions ─────────────────────────────────────────────────────────

export type UserPosition = {
  tokenId: number;
  ownerAddress: string;
  vaultAddress: string;
  supplyAsset: string;
  borrowAsset: string;
  isOpen: boolean;
  openedBlock: number;
  openedTxHash: string;
};

type UserPositionsResponse = {
  items: UserPosition[];
  nextCursor: string | null;
};

export async function fetchUserOpenPositions(
  userAddress: string,
  limit = 20
): Promise<UserPosition[]> {
  const url = `${BACKEND_URL}/api/users/${encodeURIComponent(userAddress.toLowerCase())}/positions/open?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`user-positions ${res.status}`);
  const data: UserPositionsResponse = await res.json();
  return data.items;
}

// ── Position timeline ──────────────────────────────────────────────────────

export type TimelineItem = {
  tokenId: number;
  eventType: string;
  txHash: string;
  blockNumber: number;
  eventTimestamp: string;
  userAddress: string;
  vaultAddress: string;
  metadata: string; // JSON string — parse with try/catch
};

type TimelineResponse = {
  items: TimelineItem[];
  nextCursor: string | null;
};

export async function fetchPositionTimeline(
  tokenId: number,
  limit = 20
): Promise<TimelineItem[]> {
  const url = `${BACKEND_URL}/api/positions/${tokenId}/timeline?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`timeline ${res.status}`);
  const data: TimelineResponse = await res.json();
  return data.items;
}

// ── All open positions ─────────────────────────────────────────────────────

type AllPositionsResponse = {
  items: UserPosition[];
  nextCursor: string | null;
};

export async function fetchAllOpenPositions(
  limit = 50
): Promise<UserPosition[]> {
  const url = `${BACKEND_URL}/api/positions/open?limit=${limit}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`all-positions ${res.status}`);
  const data: AllPositionsResponse = await res.json();
  return data.items;
}

// ── Tx hints ───────────────────────────────────────────────────────────────

// TODO: expand actionType to a union type once all action types are finalized
export type TxActionType = "OPEN_POSITION" | "CLOSE_POSITION" | "COLLECT_FEES";

type TxHintRequest = {
  txHash: string;
  actionType: TxActionType;
  userAddress: string;
};

export async function postTxHint(req: TxHintRequest): Promise<void> {
  const url = `${BACKEND_URL}/api/tx-hints`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!res.ok) throw new Error(`tx-hints ${res.status}`);
}
