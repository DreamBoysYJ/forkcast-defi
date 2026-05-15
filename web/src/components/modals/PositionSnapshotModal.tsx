"use client";

import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { fetchPositionSnapshots, type SnapshotItem } from "@/lib/backendApi";

function isNoDebt(s: SnapshotItem): boolean {
  return s.totalDebtBase === "0" || s.healthFactor.startsWith("9999999999");
}

// Precision-safe: formatUnits(BigInt(str), decimals), truncate (no rounding)
function fmtUnits(str: string, decimals: number, frac = 4): string {
  try {
    const full = formatUnits(BigInt(str), decimals);
    const dot = full.indexOf(".");
    return dot === -1 ? full : full.slice(0, dot + frac + 1);
  } catch {
    return str;
  }
}

// healthFactor is already a decimal string — truncate without Number()
function fmtHF(str: string, frac = 4): string {
  const dot = str.indexOf(".");
  return dot === -1 ? str : str.slice(0, dot + frac + 1);
}

function fmtTimestamp(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? iso
    : d.toLocaleString("en-GB", { hour12: false });
}

type Props = {
  isOpen: boolean;
  onClose: () => void;
  tokenId: number;
};

export function PositionSnapshotModal({ isOpen, onClose, tokenId }: Props) {
  const [snapshots, setSnapshots] = useState<SnapshotItem[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setIsLoading(true);
    setError(null);
    fetchPositionSnapshots(tokenId, 20)
      .then(setSnapshots)
      .catch((err: unknown) =>
        setError(err instanceof Error ? err.message : "Failed to load snapshots")
      )
      .finally(() => setIsLoading(false));
  }, [isOpen, tokenId]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70">
      <div className="flex max-h-[80vh] w-full max-w-5xl flex-col rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-xl">
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              State History
              <span className="ml-2 font-mono text-sm text-slate-500">
                #{tokenId}
              </span>
            </h2>
            <p className="text-xs text-slate-400">
              Periodic state snapshots · not real-time events
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"
          >
            Esc
          </button>
        </div>

        {/* Table */}
        <div className="flex-1 overflow-auto rounded-xl border border-slate-800">
          {isLoading ? (
            <div className="py-10 text-center text-xs text-slate-400">
              Loading…
            </div>
          ) : error ? (
            <div className="py-10 text-center text-xs text-red-400">
              {error}
            </div>
          ) : snapshots.length === 0 ? (
            <div className="py-10 text-center text-xs text-slate-400">
              No snapshots yet. Snapshots are recorded periodically by the
              backend job.
            </div>
          ) : (
            <table className="w-full border-collapse text-xs">
              <thead className="sticky top-0 bg-slate-900/70 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-2 text-left font-medium">
                    Snapshot At
                  </th>
                  <th className="px-4 py-2 text-right font-medium">Block</th>
                  <th className="px-4 py-2 text-right font-medium">HF</th>
                  <th className="px-4 py-2 text-right font-medium">
                    Collateral
                  </th>
                  <th className="px-4 py-2 text-right font-medium">Debt</th>
                  <th className="px-4 py-2 text-right font-medium">Amount0</th>
                  <th className="px-4 py-2 text-right font-medium">Amount1</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 bg-slate-900/60">
                {snapshots.map((s, i) => (
                  <tr
                    key={`${s.snapshotAt}-${i}`}
                    className="transition-colors hover:bg-slate-800/40"
                  >
                    <td className="px-4 py-3 font-mono text-slate-300">
                      {fmtTimestamp(s.snapshotAt)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-slate-400">
                      {s.observedBlockNumber.toLocaleString()}
                    </td>
                    <td className="px-4 py-3 text-right font-mono">
                      {isNoDebt(s) ? (
                        <span className="text-emerald-400">No Debt</span>
                      ) : (
                        <span
                          className={
                            parseFloat(s.healthFactor) >= 1.5
                              ? "text-emerald-400"
                              : parseFloat(s.healthFactor) >= 1.1
                                ? "text-amber-400"
                                : "text-red-400"
                          }
                        >
                          {fmtHF(s.healthFactor)}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-slate-300">
                      ${fmtUnits(s.totalCollateralBase, 8, 2)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-slate-300">
                      ${fmtUnits(s.totalDebtBase, 8, 2)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-slate-400">
                      {fmtUnits(s.amount0Now, 18)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-slate-400">
                      {fmtUnits(s.amount1Now, 18)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {!isLoading && !error && snapshots.length > 0 && (
          <p className="mt-3 text-right text-xs text-slate-500">
            {snapshots.length} snapshot{snapshots.length > 1 ? "s" : ""} · most
            recent first
          </p>
        )}
      </div>
    </div>
  );
}
