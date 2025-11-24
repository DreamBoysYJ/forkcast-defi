"use client";

import { AssetsToBorrowCardRow } from "./AssetsToBorrowCardRow";

export type BorrowAsset = {
  symbol: string;
  iconUrl?: string;
  available: number; // 빌릴 수 있는 수량(토큰)
  availableUsd: number; // 그 USD 가치
  borrowApy: number; // 0.05 => 5.0%
};

const demoBorrowAssets: BorrowAsset[] = [
  {
    symbol: "WBTC",
    iconUrl: "/tokens/wbtc.png",
    available: 0.3,
    availableUsd: 18000,
    borrowApy: 0.05,
  },
  {
    symbol: "USDC",
    iconUrl: "/tokens/usdc.png",
    available: 5000,
    availableUsd: 5000,
    borrowApy: 0.02,
  },
  {
    symbol: "LINK",
    iconUrl: "/tokens/link.png",
    available: 1000,
    availableUsd: 7000,
    borrowApy: 0.03,
  },
];

export function AssetsToBorrowCard() {
  return (
    <section className="mt-6 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-4">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          {/* 헤더 */}
          <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
            <h2 className="text-sm font-semibold text-slate-900">
              Assets to borrow (demo)
            </h2>
            <span className="text-[11px] text-slate-400">
              Available &amp; borrow APY (amount is still finalized in preview)
            </span>
          </div>

          {/* 테이블 */}
          <div className="overflow-x-auto">
            <table className="min-w-full border-collapse">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Asset</th>
                  <th className="px-4 py-3 text-right font-medium">
                    Available
                  </th>
                  <th className="px-4 py-3 text-right font-medium">
                    Borrow APY
                  </th>
                </tr>
              </thead>
              <tbody>
                {demoBorrowAssets.map((asset) => (
                  <AssetsToBorrowCardRow key={asset.symbol} asset={asset} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
