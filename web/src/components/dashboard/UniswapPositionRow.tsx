// components/dashboard/uniswap/UniswapPositionRow.tsx
"use client";

// ✅ 이 타입을 먼저 선언하고 export
export type UniPositionRowData = {
  tokenId: number;
  token0Symbol: string;
  token1Symbol: string;
  token0IconUrl: string;
  token1IconUrl: string;
  rangeLabel: string; // 예: "1,500 – 2,500"
  inRange: boolean;
  amount0NowLabel: string; // 예: "AAVE 100.0000"
  amount1NowLabel: string; // 예: "WBTC 0.3000"
};

type Props = {
  position: UniPositionRowData;
  onClickCollect: (p: UniPositionRowData) => void;
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

  return (
    <tr className="border-b border-slate-800/60 last:border-0">
      {/* 1) POOL */}
      <td className="px-6 py-3">
        <div className="flex items-center gap-3">
          {/* 두 개 아이콘 겹치게 */}
          <div className="flex -space-x-1">
            <img
              src={token0IconUrl}
              alt={token0Symbol}
              className="h-7 w-7 rounded-full border border-slate-900 bg-slate-950 object-cover"
            />
            <img
              src={token1IconUrl}
              alt={token1Symbol}
              className="h-7 w-7 rounded-full border border-slate-900 bg-slate-950 object-cover"
            />
          </div>
          <div className="flex flex-col">
            <span className="text-sm font-medium text-slate-50">
              {token0Symbol} / {token1Symbol}
            </span>
            <span className="text-[11px] text-slate-500">
              Position #{tokenId}
            </span>
          </div>
        </div>
      </td>

      {/* 2) RANGE */}
      <td className="px-6 py-3 text-sm text-slate-50">{rangeLabel}</td>

      {/* 3) LIQUIDITY: 현재 토큰 양 두 줄 */}
      <td className="px-6 py-3 text-right">
        <div className="text-sm font-medium text-slate-50">
          {amount0NowLabel}
        </div>
        <div className="text-sm font-medium text-slate-50">
          {amount1NowLabel}
        </div>
      </td>

      {/* 4) STATUS */}
      <td className="px-6 py-3">
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
      </td>

      {/* 5) ACTION */}
      <td className="px-6 py-3 text-right">
        <button
          className="rounded-full border border-indigo-400/40 bg-indigo-500/10 px-4 py-1.5 text-xs font-medium text-indigo-100 hover:bg-indigo-500/20"
          onClick={() => onClickCollect(position)}
        >
          Collect fees
        </button>
      </td>
    </tr>
  );
}
