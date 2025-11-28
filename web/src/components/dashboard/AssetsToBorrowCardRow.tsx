"use client";

export type BorrowAsset = {
  symbol: string;
  iconUrl?: string;
  available: number;
  availableUsd: number;
  borrowApy: number;
};

type Props = {
  asset: BorrowAsset;
};

export function AssetsToBorrowCardRow({ asset }: Props) {
  const { symbol, iconUrl, available, availableUsd, borrowApy } = asset;

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

      {/* 2) Available (tokenAmount + USD)*/}
      <td className="fc-cell fc-cell-right">
        <div className="font-medium text-slate-900 leading-tight">
          ✓{/* {available.toFixed(2)} */}
        </div>
        {/* <div className="fc-muted leading-tight">${availableUsd.toFixed(2)}</div> */}
      </td>

      {/* 3) Borrow APY */}
      <td className="fc-cell fc-cell-right">
        <span className="text-slate-900">{(borrowApy * 100).toFixed(2)}%</span>
      </td>
    </tr>
  );
}
