"use client";

import { useEffect, useState } from "react";
import { fetchAllOpenPositions, type UserPosition } from "@/lib/backendApi";

const ASSET_LABELS: Record<string, string> = {
  "0x88541670e55cc00beefd87eb59edd1b7c511ac9a": "AAVE",
  "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5": "LINK",
};

function assetLabel(addr: string): string {
  return ASSET_LABELS[addr.toLowerCase()] ?? addr.slice(0, 6) + "…";
}

function shortAddr(addr: string): string {
  return addr.slice(0, 6) + "…" + addr.slice(-4);
}

function shortHash(hash: string): string {
  return hash.slice(0, 8) + "…" + hash.slice(-6);
}

type Props = {
  isOpen: boolean;
  onClose: () => void;
};

export function AllPositionsModal({ isOpen, onClose }: Props) {
  const [positions, setPositions] = useState<UserPosition[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setIsLoading(true);
    setError(null);
    fetchAllOpenPositions(50)
      .then(setPositions)
      .catch((err: unknown) =>
        setError(err instanceof Error ? err.message : "Failed to load positions")
      )
      .finally(() => setIsLoading(false));
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70">
      <div className="flex max-h-[80vh] w-full max-w-5xl flex-col rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-xl">
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              All Active Positions
            </h2>
            <p className="text-xs text-slate-400">
              Based on backend DB · may not reflect the latest on-chain state
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
        <div className="flex-1 overflow-y-auto rounded-xl border border-slate-800">
          {isLoading ? (
            <div className="py-10 text-center text-xs text-slate-400">
              Loading…
            </div>
          ) : error ? (
            <div className="py-10 text-center text-xs text-red-400">
              {error}
            </div>
          ) : positions.length === 0 ? (
            <div className="py-10 text-center text-xs text-slate-400">
              No open positions found.
            </div>
          ) : (
            <table className="w-full border-collapse text-sm">
              <thead className="sticky top-0 bg-slate-900/70 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-2 text-left font-medium">Token ID</th>
                  <th className="px-4 py-2 text-left font-medium">Owner</th>
                  <th className="px-4 py-2 text-left font-medium">Vault</th>
                  <th className="px-4 py-2 text-left font-medium">Strategy</th>
                  <th className="px-4 py-2 text-right font-medium">Opened Block</th>
                  <th className="px-4 py-2 text-right font-medium">Tx</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 bg-slate-900/60">
                {positions.map((pos) => (
                  <tr
                    key={pos.tokenId}
                    className="transition-colors hover:bg-slate-800/40"
                  >
                    <td className="px-4 py-3 font-mono text-slate-200">
                      #{pos.tokenId}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-slate-400">
                      {shortAddr(pos.ownerAddress)}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-slate-400">
                      {shortAddr(pos.vaultAddress)}
                    </td>
                    <td className="px-4 py-3 text-slate-200">
                      <span className="text-emerald-400">
                        {assetLabel(pos.supplyAsset)}
                      </span>
                      <span className="mx-1 text-slate-500">→</span>
                      <span className="text-sky-400">
                        {assetLabel(pos.borrowAsset)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-xs text-slate-400">
                      {pos.openedBlock.toLocaleString()}
                    </td>
                    <td className="px-4 py-3 text-right font-mono text-xs">
                      <a
                        href={`https://sepolia.etherscan.io/tx/${pos.openedTxHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-slate-500 hover:text-sky-400 transition-colors"
                        title={pos.openedTxHash}
                      >
                        {shortHash(pos.openedTxHash)}
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {!isLoading && !error && positions.length > 0 && (
          <p className="mt-3 text-right text-xs text-slate-500">
            {positions.length} position{positions.length > 1 ? "s" : ""}
          </p>
        )}
      </div>
    </div>
  );
}
