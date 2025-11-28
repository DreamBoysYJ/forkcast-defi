// components/dashboard/strategy/StrategyPositionRow.tsx
"use client";

type TokenUi = {
  symbol: string;
  iconUrl?: string;
};

export type StrategyPositionRowData = {
  tokenId: number;
  isOpen: boolean;

  // strategy position
  supplyToken: TokenUi;
  borrowToken: TokenUi;
  owner: string;
  vault: string;

  // Uni v4 state
  poolToken0: TokenUi;
  poolToken1: TokenUi;
  amount0Now: number;
  amount1Now: number;
  rangeLabel: string; // ex: "1,500 – 2,500"
  currentTickLabel: string; // ex: "Current tick 1,800"
  inRange: boolean;

  // Aave risks
  totalCollateralUsd: number;
  totalDebtUsd: number;
  availableBorrowUsd: number;
  ltv: number; // 0.40 -> 40%
  liquidationThreshold: number; // 0.72 -> 72%
  healthFactor: number;
};

type Props = {
  data: StrategyPositionRowData;
  onClickPreviewClose?: (tokenId: number) => void;
};

function formatUsd(v: number) {
  return `$${v.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function formatPercent(v: number) {
  return `${(v * 100).toFixed(2)}%`;
}

function shortAddr(addr: string) {
  if (!addr) return "";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function StrategyPositionRow({ data, onClickPreviewClose }: Props) {
  const {
    tokenId,
    isOpen,
    supplyToken,
    borrowToken,
    owner,
    vault,
    poolToken0,
    poolToken1,
    amount0Now,
    amount1Now,
    rangeLabel,
    currentTickLabel,
    inRange,
    totalCollateralUsd,
    totalDebtUsd,
    availableBorrowUsd,
    ltv,
    liquidationThreshold,
    healthFactor,
  } = data;

  const borrowPowerUsedPercent =
    totalCollateralUsd > 0 && liquidationThreshold > 0
      ? (totalDebtUsd / (totalCollateralUsd * liquidationThreshold)) * 100
      : 0;
  const handleClickPreview = () => {
    if (!onClickPreviewClose) return;
    onClickPreviewClose(data.tokenId);
  };

  let hfColor = "text-emerald-300";
  if (healthFactor < 1.1) hfColor = "text-rose-300";
  else if (healthFactor < 1.3) hfColor = "text-amber-300";

  return (
    <div className="grid gap-6 md:grid-cols-3">
      {/* 1) Strategy structure Block */}
      <div className="flex flex-col gap-3">
        <div className="text-xs font-medium uppercase tracking-wide text-slate-400">
          Strategy composition
        </div>

        <div className="space-y-2">
          {/* Supply */}
          <div className="flex items-center gap-2">
            {supplyToken.iconUrl && (
              <img
                src={supplyToken.iconUrl}
                alt={supplyToken.symbol}
                className="h-5 w-5 rounded-full border border-slate-900 bg-slate-950 object-cover"
              />
            )}
            <div className="flex flex-col">
              <span className="text-sm font-medium text-slate-50">
                Supply (collateral)
              </span>
              <span className="text-xs text-slate-400">
                {supplyToken.symbol}
              </span>
            </div>
          </div>

          {/* Borrow */}
          <div className="flex items-center gap-2">
            {borrowToken.iconUrl && (
              <img
                src={borrowToken.iconUrl}
                alt={borrowToken.symbol}
                className="h-5 w-5 rounded-full border border-slate-900 bg-slate-950 object-cover"
              />
            )}
            <div className="flex flex-col">
              <span className="text-sm font-medium text-slate-50">
                Borrow asset
              </span>
              <span className="text-xs text-slate-400">
                {borrowToken.symbol}
              </span>
            </div>
          </div>
        </div>

        <div className="mt-2 space-y-1 text-[11px] text-slate-500">
          <div>Token ID: #{tokenId}</div>
          <div>Owner: {shortAddr(owner)}</div>
          <div>Vault: {shortAddr(vault)}</div>
        </div>

        <div className="mt-2">
          <span
            className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium ${
              isOpen
                ? "bg-emerald-500/10 text-emerald-300"
                : "bg-slate-700/40 text-slate-300"
            }`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${
                isOpen ? "bg-emerald-400" : "bg-slate-400"
              }`}
            />
            {isOpen ? "Open" : "Closed"}
          </span>
        </div>
      </div>

      {/* 2) Uni v4 Position Block */}
      <div className="flex flex-col gap-3">
        <div className="text-xs font-medium uppercase tracking-wide text-slate-400">
          Uniswap v4 position
        </div>

        <div className="flex items-center gap-3">
          {/* Overlap two icons in pool  */}
          <div className="flex -space-x-1">
            {poolToken0.iconUrl && (
              <img
                src={poolToken0.iconUrl}
                alt={poolToken0.symbol}
                className="h-7 w-7 rounded-full border border-slate-900 bg-slate-950 object-cover"
              />
            )}
            {poolToken1.iconUrl && (
              <img
                src={poolToken1.iconUrl}
                alt={poolToken1.symbol}
                className="h-7 w-7 rounded-full border border-slate-900 bg-slate-950 object-cover"
              />
            )}
          </div>
          <div className="flex flex-col">
            <span className="text-sm font-medium text-slate-50">
              {poolToken0.symbol} / {poolToken1.symbol}
            </span>
            <span className="text-[11px] text-slate-500">{rangeLabel}</span>
          </div>
        </div>

        <div className="mt-2 space-y-1 text-sm">
          <div className="flex justify-between text-slate-50">
            <span>{poolToken0.symbol}</span>
            <span>{amount0Now.toFixed(4)}</span>
          </div>
          <div className="flex justify-between text-slate-50">
            <span>{poolToken1.symbol}</span>
            <span>{amount1Now.toFixed(4)}</span>
          </div>
          <div className="text-[11px] text-slate-500">{currentTickLabel}</div>
        </div>

        <div className="mt-2">
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

      {/* 3) Aave risks block */}
      <div className="flex flex-col justify-between gap-3">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-slate-400">
            Aave account risk
          </div>

          <div className="mt-2">
            <div className="text-[11px] uppercase tracking-wide text-slate-400">
              Health factor
            </div>
            <div className={`text-xl font-semibold ${hfColor}`}>
              {healthFactor.toFixed(2)}
            </div>
          </div>

          <div className="mt-3 space-y-1 text-sm">
            <div className="flex justify-between">
              <span className="text-slate-400">Collateral</span>
              <span className="text-slate-50">
                {formatUsd(totalCollateralUsd)}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-slate-400">Debt</span>
              <span className="text-slate-50">{formatUsd(totalDebtUsd)}</span>
            </div>
            <div className="flex justify-between text-xs text-slate-400">
              <span>Available to borrow</span>
              <span className="text-slate-300">
                {formatUsd(availableBorrowUsd)}
              </span>
            </div>
          </div>

          <div className="mt-2 grid grid-cols-2 gap-2 text-[11px] text-slate-400">
            <div>
              <div className="uppercase tracking-wide">LTV</div>
              <div className="text-slate-200">{formatPercent(ltv)}</div>
            </div>
            <div>
              <div className="uppercase tracking-wide">Liq. threshold</div>
              <div className="text-slate-200">
                {formatPercent(liquidationThreshold)}
              </div>
            </div>
            <div>
              <div className="uppercase tracking-wide">Borrow used</div>
              <div className="text-slate-200">
                {borrowPowerUsedPercent.toFixed(2)}%
              </div>
            </div>
          </div>
        </div>

        <div className="flex justify-end">
          <button
            className="rounded-full border border-indigo-400/40 bg-indigo-500/10 px-4 py-1.5 text-xs font-medium text-indigo-100 hover:bg-indigo-500/20"
            onClick={handleClickPreview}
          >
            Preview close
          </button>
        </div>
      </div>
    </div>
  );
}
