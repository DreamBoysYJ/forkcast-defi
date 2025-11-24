"use client";

import {
  AssetsToSupplyCardRow,
  type SupplyAsset,
} from "./AssetsToSupplyCardRow";

type Props = {
  onClickPreview?: (symbol: string) => void;
};

const demoAssets: SupplyAsset[] = [
  {
    symbol: "AAVE",
    iconUrl: "/tokens/aave.png",
    supplied: 100,
    suppliedUsd: 3000,
    apy: 0.03,
    canBeCollateral: true,
    isStrategyAsset: true,
  },
  {
    symbol: "USDC",
    iconUrl: "/tokens/usdc.png",
    supplied: 500,
    suppliedUsd: 500,
    apy: 0.02,
    canBeCollateral: true,
  },
];

export function AssetsToSupplyCard({ onClickPreview }: Props) {
  return (
    <section className="mt-10 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-4">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
            <h2 className="text-sm font-semibold text-slate-900">
              Assets to supply (demo)
            </h2>
            <span className="text-[11px] text-slate-400">
              Demo data (Aave V3 style)
            </span>
          </div>

          <div className="overflow-x-auto">
            <table className="min-w-full border-collapse">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Asset</th>
                  <th className="px-4 py-3 text-right font-medium">Balance</th>
                  <th className="px-4 py-3 text-right font-medium">APY</th>
                  <th className="px-4 py-3 text-center font-medium">Collat</th>
                  <th className="px-4 py-3 text-right font-medium">Action</th>
                </tr>
              </thead>
              <tbody>
                {demoAssets.map((asset) => (
                  <AssetsToSupplyCardRow
                    key={asset.symbol}
                    asset={asset}
                    onClickStrategy={(a) => {
                      onClickPreview?.(a.symbol);
                    }}
                  />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
