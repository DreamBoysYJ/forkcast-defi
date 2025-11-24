"use client";

export type YourSupply = {
  symbol: string; // 예: "AAVE"
  iconUrl?: string; // 예: "/tokens/aave.png"
  supplied: number; // 예치 수량 (토큰)
  suppliedUsd: number; // 예치 USD 가치
  apy: number; // 0.03 => 3.0%
  isCollateral: boolean;
};

type Props = {
  item: YourSupply;
};

export function YourSupplyRow({ item }: Props) {
  const { symbol, iconUrl, supplied, suppliedUsd, apy, isCollateral } = item;

  return (
    <tr className="fc-row">
      {/* 1) Asset (아이콘 + 심볼) */}
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

      {/* 2) Balance (토큰 수량 + USD) */}
      <td className="fc-cell fc-cell-right">
        <div className="font-medium text-slate-900 leading-tight">
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
