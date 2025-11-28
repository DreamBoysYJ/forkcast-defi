// src/components/dashboard/uniswap/UniswapPositionRow.tsx
"use client";

export type UniPositionRowData = {
  tokenId: number;
  token0Symbol: string;
  token1Symbol: string;
  token0IconUrl: string;
  token1IconUrl: string;
  rangeLabel: string;
  inRange: boolean;
  amount0NowLabel: string; // ex: "AAVE 70.83"
  amount1NowLabel: string; // ex: "LINK 12.34"
};

type Props = {
  position: UniPositionRowData;
  onClickCollect: (pos: UniPositionRowData) => void;
};

export function UniswapPositionRow({ position, onClickCollect }: Props) {
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

  const statusLabel = inRange ? "In range" : "Out of range";
  const statusDotClass = inRange ? "bg-emerald-400" : "bg-amber-400";
  const statusBgClass = inRange ? "bg-emerald-950/60" : "bg-amber-950/60";
  const statusTextClass = inRange ? "text-emerald-200" : "text-amber-200";

  return (
    <tr className="border-t border-slate-800/70">
      {/* Pool */}
      <td className="px-6 py-4 align-middle">
        <div className="flex items-center gap-3">
          <div className="flex -space-x-2">
            <div className="h-8 w-8 overflow-hidden rounded-full border border-slate-900 bg-slate-800">
              <img
                src={token0IconUrl}
                alt={token0Symbol}
                className="h-full w-full object-cover"
              />
            </div>
            <div className="h-8 w-8 overflow-hidden rounded-full border border-slate-900 bg-slate-800">
              <img
                src={token1IconUrl}
                alt={token1Symbol}
                className="h-full w-full object-cover"
              />
            </div>
          </div>
          <div className="flex flex-col">
            <span className="text-sm font-medium text-slate-50">
              {token0Symbol} / {token1Symbol}
            </span>
            <span className="text-[11px] text-slate-400">
              Position #{tokenId}
            </span>
          </div>
        </div>
      </td>

      {/* Range */}
      <td className="px-6 py-4 align-middle">
        <span className="text-sm text-slate-100">{rangeLabel}</span>
      </td>

      {/* Liquidity */}
      <td className="px-6 py-4 align-middle">
        <div className="flex flex-col text-sm text-slate-100">
          <span>{amount0NowLabel}</span>
          <span>{amount1NowLabel}</span>
        </div>
      </td>

      {/* Status */}
      <td className="px-6 py-4 align-middle">
        <span
          className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-[11px] font-medium ${statusBgClass} ${statusTextClass}`}
        >
          <span className={`h-1.5 w-1.5 rounded-full ${statusDotClass}`} />
          {statusLabel}
        </span>
      </td>

      {/* Action */}
      <td className="px-6 py-4 align-middle text-right">
        <button
          onClick={() => onClickCollect(position)}
          className="rounded-full bg-indigo-500 px-4 py-1.5 text-xs font-semibold text-slate-50 hover:bg-indigo-400"
        >
          Collect fees
        </button>
      </td>
    </tr>
  );
}
