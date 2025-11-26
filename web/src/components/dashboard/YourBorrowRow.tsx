"use client";

export type YourBorrow = {
  symbol: string; // 예: "WBTC"
  iconUrl?: string; // 예: "/tokens/wbtc.png"
  debtToken: number;
  debtUsd: number; // 총 대출 USD
  borrowApy: number; // 0.05 -> 5.0%
  borrowPowerUsed: number; // 0.006 -> 0.6%
};

type Props = {
  item: YourBorrow;
};

export function YourBorrowRow({ item }: Props) {
  const { symbol, iconUrl, debtToken, debtUsd, borrowApy, borrowPowerUsed } =
    item;

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

      {/* 2) Debt (총 대출 USD) */}
      <td className="fc-cell fc-cell-right">
        <div className="font-medium text-slate-900 leading-tight">
          {debtToken.toFixed(2)}
        </div>
        <div className="fc-muted leading-tight">
          $
          {debtUsd.toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          })}
        </div>
      </td>

      {/* 3) Borrow APY */}
      <td className="fc-cell fc-cell-right">
        <span className="text-slate-900">{(borrowApy * 100).toFixed(2)}%</span>
      </td>

      {/* 4) Borrow power used */}
      <td className="fc-cell fc-cell-right">
        <span className="text-slate-900">
          {(borrowPowerUsed * 100).toFixed(2)}%
        </span>
      </td>
    </tr>
  );
}
