"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import { formatUnits } from "viem";
import {
  fetchUserOpenPositions,
  fetchPositionTimeline,
  type TimelineItem,
} from "@/lib/backendApi";

// ── Event type badge ───────────────────────────────────────────────────────

const EVENT_BADGE: Record<string, { label: string; cls: string }> = {
  OPENED: {
    label: "Opened",
    cls: "border-emerald-500/40 bg-emerald-500/15 text-emerald-200",
  },
  CLOSED: {
    label: "Closed",
    cls: "border-slate-500/40 bg-slate-500/15 text-slate-300",
  },
  LIQUIDITY_ADDED: {
    label: "Liquidity added",
    cls: "border-indigo-500/40 bg-indigo-500/15 text-indigo-200",
  },
  LIQUIDITY_REMOVED: {
    label: "Liquidity removed",
    cls: "border-amber-500/40 bg-amber-500/15 text-amber-200",
  },
  FEES_COLLECTED: {
    label: "Fees collected",
    cls: "border-sky-500/40 bg-sky-500/15 text-sky-200",
  },
};

function EventBadge({ eventType }: { eventType: string }) {
  const meta = EVENT_BADGE[eventType] ?? {
    label: eventType,
    cls: "border-slate-600/40 bg-slate-600/15 text-slate-300",
  };
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-[10px] font-medium ${meta.cls}`}
    >
      {meta.label}
    </span>
  );
}

// ── Metadata preview ───────────────────────────────────────────────────────

const AMOUNT_LABELS: Record<string, string> = {
  supplyAmount:   "Supply",
  borrowedAmount: "Borrow",
  spent0:         "Spent 0",
  spent1:         "Spent 1",
  amount0:        "Fee 0",
  amount1:        "Fee 1",
};

function formatWei(val: string): string {
  try {
    const num = parseFloat(formatUnits(BigInt(val), 18));
    if (num === 0) return "0";
    return num.toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 4,
    });
  } catch {
    return val;
  }
}

function MetadataPreview({ raw }: { raw: string }) {
  let parsedObj: Record<string, unknown> | null = null;
  try {
    parsedObj = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return null;
  }
  if (!parsedObj) return null;
  const fields = Object.entries(AMOUNT_LABELS).filter(([k]) => k in parsedObj!);
  if (fields.length === 0) return null;
  return (
    <div className="mt-1 flex flex-wrap gap-3 text-[10px] text-slate-500">
      {fields.map(([k, label]) => (
        <span key={k}>
          {label}{" "}
          <span className="font-medium text-slate-300">
            {formatWei(String(parsedObj![k]))}
          </span>
        </span>
      ))}
    </div>
  );
}

// ── Timeline row ───────────────────────────────────────────────────────────

function formatTimestamp(iso: string) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? iso
    : d.toLocaleString("en-GB", { hour12: false });
}

function TimelineRow({ item }: { item: TimelineItem }) {
  return (
    <div className="flex items-start justify-between px-6 py-3 text-[11px] text-slate-200">
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-2">
          <EventBadge eventType={item.eventType} />
          <span className="text-[10px] text-slate-400">
            Block {item.blockNumber}
          </span>
        </div>
        <div className="text-[10px] text-slate-500">
          tx {item.txHash.slice(0, 10)}…
        </div>
        {item.metadata && <MetadataPreview raw={item.metadata} />}
      </div>
      <div className="ml-4 shrink-0 text-right text-[10px] text-slate-400">
        {formatTimestamp(item.eventTimestamp)}
      </div>
    </div>
  );
}

// ── Collapsible per-position timeline ─────────────────────────────────────

function CollapsibleTimeline({ tokenId }: { tokenId: number }) {
  const [isOpen, setIsOpen] = useState(false);

  const { data: timeline, isLoading, isError } = useQuery({
    queryKey: ["position-timeline", tokenId],
    queryFn: () => fetchPositionTimeline(tokenId, 20),
    enabled: isOpen,
    staleTime: 30_000,
  });

  return (
    <div className="border-t border-slate-800/60 first:border-t-0">
      {/* Clickable header */}
      <button
        onClick={() => setIsOpen((v) => !v)}
        className="flex w-full items-center justify-between px-6 py-3 text-left hover:bg-slate-800/30"
      >
        <span className="text-[11px] font-medium text-slate-300">
          Token #{tokenId}
        </span>
        <span className="text-[10px] text-slate-500">
          {isOpen ? "▲ collapse" : "▼ expand"}
        </span>
      </button>

      {/* Timeline body */}
      {isOpen && (
        <div className="bg-slate-900/40">
          {isLoading ? (
            <div className="px-6 py-4 text-center text-[11px] text-slate-400">
              Loading…
            </div>
          ) : isError ? (
            <div className="px-6 py-4 text-center text-[11px] text-red-400">
              Failed to load timeline.
            </div>
          ) : !timeline || timeline.length === 0 ? (
            <div className="px-6 py-4 text-center text-[11px] text-slate-400">
              No activity recorded yet.
            </div>
          ) : (
            <div className="divide-y divide-slate-800/80">
              {timeline.map((item) => (
                <TimelineRow
                  key={`${item.txHash}-${item.eventType}`}
                  item={item}
                />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ── Section ────────────────────────────────────────────────────────────────

export function PositionActivitySection() {
  const { address } = useAccount();

  const {
    data: positions,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ["user-open-positions", address],
    queryFn: () => fetchUserOpenPositions(address!, 20),
    enabled: !!address,
    staleTime: 30_000,
  });

  const hasNoPositions =
    !isLoading && !isError && positions !== undefined && positions.length === 0;

  return (
    <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-slate-800/60 px-6 py-4">
        <div className="flex flex-col">
          <h2 className="text-[15px] font-semibold text-slate-50">
            Position activity
          </h2>
          <p className="text-[11px] text-slate-400">
            Click a position to expand its timeline
          </p>
        </div>
        {positions && positions.length > 0 && (
          <span className="text-[11px] text-slate-500">
            {positions.length} position{positions.length > 1 ? "s" : ""}
          </span>
        )}
      </div>

      {/* Body */}
      <div className="overflow-hidden rounded-b-2xl">
        {!address ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            Connect wallet to see position activity.
          </div>
        ) : isLoading ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            Loading positions…
          </div>
        ) : isError ? (
          <div className="px-6 py-6 text-center text-[11px] text-red-400">
            Failed to load positions. Check backend connection.
          </div>
        ) : hasNoPositions ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            No open positions found.
          </div>
        ) : (
          <div>
            {positions!.map((pos) => (
              <CollapsibleTimeline key={pos.tokenId} tokenId={pos.tokenId} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
