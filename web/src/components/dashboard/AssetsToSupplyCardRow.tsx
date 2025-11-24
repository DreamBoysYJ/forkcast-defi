"use client";

import type { ReactNode } from "react";

export type SupplyAsset = {
  symbol: string;
  iconUrl?: string;
  supplied: number;
  suppliedUsd: number;
  apy: number;
  canBeCollateral: boolean;
  isStrategyAsset?: boolean;
};

type Props = {
  asset: SupplyAsset;
  onClickStrategy?: (asset: SupplyAsset) => void;
  extraCell?: ReactNode;
};

export function AssetsToSupplyCardRow({
  asset,
  onClickStrategy,
  extraCell,
}: Props) {
  const {
    symbol,
    iconUrl,
    supplied,
    suppliedUsd,
    apy,
    canBeCollateral,
    isStrategyAsset,
  } = asset;

  const handleClick = () => {
    if (isStrategyAsset && onClickStrategy) {
      onClickStrategy(asset);
    }
  };

  return (
    <tr className="border-b border-slate-100 last:border-0">
      {/* Asset */}
      <td className="px-4 py-3">
        <div className="flex items-center gap-2">
          {iconUrl ? (
            <img
              src={iconUrl}
              alt={symbol}
              className="h-6 w-6 rounded-full object-cover"
            />
          ) : (
            <div className="h-6 w-6 rounded-full bg-slate-200" />
          )}
          <span className="text-sm font-medium text-slate-900">{symbol}</span>
        </div>
      </td>

      {/* Balance */}
      <td className="px-4 py-3 text-right">
        <div className="text-sm font-medium text-slate-900">
          {supplied.toFixed(2)}
        </div>
        <div className="text-[11px] text-slate-500">
          ${suppliedUsd.toFixed(2)}
        </div>
      </td>

      {/* APY */}
      <td className="px-4 py-3 text-right text-sm text-slate-900">
        {(apy * 100).toFixed(2)}%
      </td>

      {/* Collat */}
      <td className="px-4 py-3 text-center text-sm text-slate-900">
        {canBeCollateral ? "✓" : "-"}
      </td>

      {/* Action */}
      <td className="px-4 py-3 text-right">
        {isStrategyAsset ? (
          <button
            onClick={handleClick}
            className="rounded-full border border-indigo-200 bg-indigo-50 px-3 py-1 text-[11px] font-medium text-indigo-700 hover:bg-indigo-100"
          >
            Preview strategy
          </button>
        ) : extraCell ? (
          extraCell
        ) : (
          <span className="text-[11px] text-slate-400">–</span>
        )}
      </td>
    </tr>
  );
}
