"use client";

import { useHookEventStore, UiHookEvent } from "@/store/useHookEventStore";

function sqrtPriceX96ToPrice(sqrtPriceX96: string): number {
  const sqrt = BigInt(sqrtPriceX96);
  const Q192 = 1n << 192n;
  const priceX1e18 = (sqrt * sqrt * 10n ** 18n) / Q192;
  return Number(priceX1e18) / 1e18;
}

function formatTimestamp(ms: number) {
  return new Date(ms).toLocaleString();
}

function HookEventRow({ event }: { event: UiHookEvent }) {
  const price = sqrtPriceX96ToPrice(event.sqrtPriceX96);
  const dateLabel = formatTimestamp(event.timestampMs);

  const sourceLabel =
    event.source === "DEMO_TRADER" ? "Demo trader swap" : "Your swap";

  return (
    <div className="flex items-start justify-between px-6 py-3 text-[11px] text-slate-200">
      {/* Left */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-2">
          <span className="rounded-full bg-indigo-500/10 px-2 py-0.5 text-[10px] font-medium text-indigo-300">
            {sourceLabel}
          </span>
          <span className="text-[10px] text-slate-400">
            PoolId {event.poolId.slice(0, 10)}…
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-3 text-[11px] text-slate-100">
          <span>
            Price ≈{" "}
            <span className="font-semibold">
              {price.toFixed(3)} LINK per AAVE
            </span>
          </span>
          <span className="text-slate-400">•</span>
          <span className="text-slate-300">Tick {event.tick}</span>
        </div>

        <div className="text-[10px] text-slate-500">
          tx {event.txHash.slice(0, 10)}…
        </div>
      </div>

      {/* Right */}
      <div className="ml-4 shrink-0 text-right text-[10px] text-slate-400">
        {dateLabel}
      </div>
    </div>
  );
}

export function HookEventSection() {
  const events = useHookEventStore((s) => s.events);

  return (
    <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 px-6 pt-4 pb-3 shadow-sm">
      {/* Header */}
      <div className="flex items-center justify-between px-6 py-4">
        <h2 className="text-[15px] font-semibold text-slate-50">
          Swap & price events
        </h2>
        <span className="text-[11px] text-slate-400">
          from Uniswap v4 hook (afterSwap)
        </span>
      </div>

      {/* Body */}
      <div className="overflow-hidden rounded-3xl border-t border-slate-800/80 bg-slate-950/40">
        {events.length === 0 ? (
          <div className="px-6 py-6 text-center text-[11px] text-slate-400">
            No hook events yet. Run the demo trader or open/close a position to
            see live swaps here.
          </div>
        ) : (
          <div className="max-h-72 divide-y divide-slate-800/80 bg-slate-900/60">
            {events
              .slice()
              .reverse()
              .map((event) => (
                <HookEventRow key={event.id} event={event} />
              ))}
          </div>
        )}
      </div>
    </section>
  );
}
