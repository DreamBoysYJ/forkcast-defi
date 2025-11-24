// components/modals/CollectFeesModal.tsx
"use client";

import type { UniPositionRowData } from "../dashboard/UniswapPositionRow";

type CollectFeesModalProps = {
  isOpen: boolean;
  onClose: () => void;
  position: UniPositionRowData | null;
  isProcessing: boolean;
  onConfirm: () => Promise<void>;
};

export function CollectFeesModal({
  isOpen,
  onClose,
  position,
  isProcessing,
  onConfirm,
}: CollectFeesModalProps) {
  if (!isOpen || !position) return null;

  const {
    tokenId,
    token0Symbol,
    token1Symbol,
    token0IconUrl,
    token1IconUrl,
    rangeLabel,
    inRange,
    amount0NowLabel,
    amount1NowLabel,
  } = position;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70">
      <div className="w-full max-w-lg rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-xl">
        {/* Header */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              Collect Uniswap v4 fees
            </h2>
            <p className="text-xs text-slate-400">
              Fees (if any) from this LP position will be sent to your wallet.
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"
          >
            Esc
          </button>
        </div>

        {/* Body */}
        <div className="space-y-4">
          {/* Pool summary */}
          <div className="flex items-center justify-between rounded-xl border border-slate-800 bg-slate-900/80 p-4">
            <div className="flex items-center gap-3">
              <div className="flex -space-x-1">
                <img
                  src={token0IconUrl}
                  alt={token0Symbol}
                  className="h-8 w-8 rounded-full border border-slate-900 bg-slate-950 object-cover"
                />
                <img
                  src={token1IconUrl}
                  alt={token1Symbol}
                  className="h-8 w-8 rounded-full border border-slate-900 bg-slate-950 object-cover"
                />
              </div>
              <div className="flex flex-col">
                <span className="text-sm font-semibold text-slate-50">
                  {token0Symbol} / {token1Symbol}
                </span>
                <span className="text-[11px] text-slate-400">
                  Position #{tokenId} · {rangeLabel}
                </span>
              </div>
            </div>
            <div>
              {inRange ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2.5 py-1 text-[11px] font-medium text-emerald-300">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                  In range
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2.5 py-1 text-[11px] font-medium text-amber-300">
                  <span className="h-1.5 w-1.5 rounded-full bg-amber-400" />
                  Out of range
                </span>
              )}
            </div>
          </div>

          {/* Current LP amounts (그냥 참고용) */}
          <div className="grid grid-cols-2 gap-4 rounded-xl border border-slate-800 bg-slate-900/80 p-4 text-sm">
            <div>
              <div className="text-xs text-slate-400">Current LP amounts</div>
              <div className="mt-1 text-slate-50">{amount0NowLabel}</div>
              <div className="text-slate-50">{amount1NowLabel}</div>
            </div>
            <div className="text-xs text-slate-400 leading-relaxed">
              This action will only collect **fees** from the position. Your
              liquidity, Aave supply/borrow and health factor will stay the
              same.
            </div>
          </div>

          <p className="text-[11px] text-slate-500">
            If the position has no accrued fees yet, this transaction will
            simply do nothing.
          </p>
        </div>

        {/* Footer */}
        <div className="mt-6 flex items-center justify-end gap-3">
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-4 py-2 text-xs font-medium text-slate-200 hover:bg-slate-800"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={isProcessing}
            className="rounded-full bg-indigo-500 px-5 py-2 text-xs font-semibold text-slate-950 hover:bg-indigo-400 disabled:opacity-60"
          >
            {isProcessing ? "Collecting…" : "Confirm collect fees"}
          </button>
        </div>
      </div>
    </div>
  );
}
