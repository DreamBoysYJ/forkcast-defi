"use client";

import { useState } from "react";

type DemoTraderModalProps = {
  isOpen: boolean;
  onClose: () => void;
};

// ✅ 백엔드 /api/demo-trader/run 응답 타입
type DemoTraderApiResponse = {
  ok: boolean;
  result: {
    blockNumber: string;
    swaps: number;
    txHashes: `0x${string}`[];
    hookEvents: {
      txHash: `0x${string}`;
      poolId: `0x${string}`;
      tick: number;
      sqrtPriceX96: string; // string으로 온다 (BigInt toString)
      timestamp: string; // block.timestamp (seconds, string)
    }[];
  };
};

export function DemoTraderModal({ isOpen, onClose }: DemoTraderModalProps) {
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (!isOpen) return null;

  const handleRunDemoTrader = async () => {
    setIsSubmitting(true);

    try {
      const res = await fetch("/api/demo-trader/run", {
        method: "POST",
      });

      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || "Request failed");
      }

      const data = (await res.json()) as DemoTraderApiResponse;

      console.log("[demo-trader] raw response", data);

      const { result } = data;

      const msg =
        `Demo trader finished.\n` +
        `Swaps: ${result.swaps}, Hook events: ${result.hookEvents.length}`;

      alert(msg);
      onClose();
    } catch (err: any) {
      console.error("[demo-trader] front error", err);
      const msg =
        err?.message ??
        "Failed to run demo trader. Please check server logs or try again.";
      alert(msg);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/70 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-base font-semibold text-slate-900">
            Run demo trader
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-sm text-slate-400 hover:text-slate-600"
            disabled={isSubmitting}
          >
            ✕
          </button>
        </div>

        {/* Body description */}
        <p className="text-sm leading-relaxed text-slate-700">
          The demo trader uses a pre-funded wallet to perform
          <br />
          <span className="font-medium">
            small swaps in the AAVE / LINK pool
          </span>{" "}
          back and forth,
          <br />
          so that your Uniswap v4 LP position can start earning fees.
        </p>
        <p className="mt-3 text-[11px] text-slate-400">
          • This runs only on the Sepolia testnet – no real funds are used.
          <br />• With one click, the backend will trigger multiple swaps using
          a dedicated “demo trader” wallet.
        </p>

        {/* Buttons */}
        <div className="mt-6 flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-slate-200 px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-50"
            disabled={isSubmitting}
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleRunDemoTrader}
            disabled={isSubmitting}
            className="rounded-lg bg-indigo-600 px-4 py-2 text-xs font-semibold text-white shadow-sm hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isSubmitting ? "Running..." : "Run demo trader"}
          </button>
        </div>
      </div>
    </div>
  );
}
