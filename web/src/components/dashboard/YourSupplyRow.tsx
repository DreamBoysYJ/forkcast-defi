// src/components/YourSupplyRow.tsx
"use client";

export type YourSupply = {
  symbol: string; // ex: "AAVE"
  iconUrl?: string; // ex: "/tokens/aave.png"
  supplied: number; // supplied amounts
  suppliedUsd: number; // supplied amounts - USD value
  apy: number; // ex : 0.03 => 3.0%
  isCollateral: boolean;
};

type Props = {
  item: YourSupply;
};

export function YourSupplyRow({ item }: Props) {
  const { symbol, iconUrl, supplied, suppliedUsd, apy, isCollateral } = item;

  return (
    <tr className="fc-row">
      {/* 1) Asset (icon + symbol) */}
      <td className="fc-cell fc-cell-left">
        <div className="fc-asset-main">
          {iconUrl ? (
            <img src={iconUrl} alt={symbol} className="fc-asset-icon" />
          ) : (
            <div className="fc-asset-icon bg-slate-200" />
          )}
          <span className="fc-asset-symbol">{symbol}</span>
        </div>
      </td>

      {/* 2) Balance (tokenAmount+ USD) */}
      <td className="fc-cell fc-cell-right">
        <div className="font-medium leading-tight text-slate-900">
          {supplied.toFixed(2)}
        </div>
        <div className="fc-muted leading-tight">${suppliedUsd.toFixed(2)}</div>
      </td>

      {/* 3) APY */}
      <td className="fc-cell fc-cell-right">
        <span className="text-slate-900">{(apy * 100).toFixed(2)}%</span>
      </td>

      {/* 4) Collat */}
      <td className="fc-cell fc-cell-right">
        <span className="text-slate-900">{isCollateral ? "✓" : "–"}</span>
      </td>
    </tr>
  );
}
