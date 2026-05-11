"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchPriceEvents, type PriceEventItem } from "@/lib/backendApi";

const POOL_ID = process.env.NEXT_PUBLIC_POOL_ID ?? "";

// ── Sparkline ─────────────────────────────────────────────────────────────

function TickSparkline({ items }: { items: PriceEventItem[] }) {
  // backend returns newest-first → reverse to chronological for left-to-right chart
  const pts = [...items].reverse();
  if (pts.length < 2) return null;

  const ticks = pts.map((p) => p.tick);
  const minT = Math.min(...ticks);
  const maxT = Math.max(...ticks);
  const rangeT = maxT - minT || 1;

  const W = 400;
  const H = 56;
  const PAD = 6;
  const innerW = W - PAD * 2;
  const innerH = H - PAD * 2;

  const pointStr = pts
    .map((p, i) => {
      const x = PAD + (i / (pts.length - 1)) * innerW;
      const y = PAD + (1 - (p.tick - minT) / rangeT) * innerH;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  const lastPt = pts[pts.length - 1];
  const lastX = PAD + innerW;
  const lastY =
    PAD + (1 - (lastPt.tick - minT) / rangeT) * innerH;

  return (
    <div className="px-6 pt-4 pb-2">
      <div className="flex items-center justify-between mb-1 text-[10px] text-slate-500">
        <span>tick chart (latest {pts.length})</span>
        <span>
          {minT} – {maxT}
        </span>
      </div>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        className="w-full"
        style={{ height: "56px" }}
      >
        {/* subtle fill area */}
        <linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#6366f1" stopOpacity="0.18" />
          <stop offset="100%" stopColor="#6366f1" stopOpacity="0" />
        </linearGradient>
        <polygon
          fill="url(#sparkFill)"
          points={`${PAD},${H - PAD} ${pointStr} ${lastX},${H - PAD}`}
        />
        <polyline
          fill="none"
          stroke="#818cf8"
          strokeWidth="1.5"
          strokeLinejoin="round"
          strokeLinecap="round"
          points={pointStr}
        />
        {/* latest dot */}
        <circle cx={lastX} cy={lastY} r="3" fill="#818cf8" />
      </svg>
    </div>
  );
}

// ── Event row ──────────────────────────────────────────────────────────────

function formatTimestamp(iso: string) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? iso
    : d.toLocaleString("en-GB", { hour12: false });
}

function PriceEventRow({ event }: { event: PriceEventItem }) {
  return (
    <div className="flex items-start justify-between px-6 py-3 text-[11px] text-slate-200">
      {/* Left */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-2">
          <span className="inline-flex items-center rounded-full border border-indigo-500/40 bg-indigo-500/15 px-2.5 py-0.5 text-[10px] font-medium text-indigo-200">
            On-chain
          </span>
          <span className="text-[10px] text-slate-400">
            Pool {event.poolId.slice(0, 10)}…
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-3 text-[11px] text-slate-100">
          <span>
            Tick{" "}
            <span className="font-semibold">{event.tick}</span>
          </span>
          <span className="text-slate-400">•</span>
          <span className="text-slate-300">Block {event.blockNumber}</span>
        </div>

        <div className="text-[10px] text-slate-500">
          tx {event.txHash.slice(0, 10)}…
        </div>
      </div>

      {/* Right */}
      <div className="ml-4 shrink-0 text-right text-[10px] text-slate-400">
        {formatTimestamp(event.eventTimestamp)}
      </div>
    </div>
  );
}

// ── Section ────────────────────────────────────────────────────────────────

export function HookEventSection() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["price-events", POOL_ID],
    queryFn: () => fetchPriceEvents(POOL_ID, 20),
    enabled: !!POOL_ID,
    staleTime: 30_000,
    refetchInterval: 60_000,
  });

  const events = data ?? [];

  return (
    <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4">
        <h2 className="text-[15px] font-semibold text-slate-50">
          Swap &amp; price events
        </h2>
        <span className="text-[11px] text-slate-400">
          from Uniswap v4 hook (afterSwap)
        </span>
      </div>

      {/* Sparkline */}
      {!isLoading && !isError && events.length >= 2 && (
        <div className="border-t border-slate-800/60">
          <TickSparkline items={events} />
        </div>
      )}

      {/* Event list */}
      <div className="overflow-hidden rounded-b-2xl border-t border-slate-800/80 bg-slate-950/40">
        {isLoading ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            Loading price events…
          </div>
        ) : isError ? (
          <div className="px-6 py-6 text-center text-[11px] text-red-400">
            Failed to load price events. Check backend connection.
          </div>
        ) : !POOL_ID ? (
          <div className="px-6 py-6 text-center text-[11px] text-amber-400">
            NEXT_PUBLIC_POOL_ID is not configured.
          </div>
        ) : events.length === 0 ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            No hook events yet. Run the demo trader or open/close a position to
            see live swaps here.
          </div>
        ) : (
          <div className="max-h-72 divide-y divide-slate-800/80 overflow-y-auto bg-slate-900/60">
            {events.map((event) => (
              <PriceEventRow key={`${event.txHash}-${event.blockNumber}`} event={event} />
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
