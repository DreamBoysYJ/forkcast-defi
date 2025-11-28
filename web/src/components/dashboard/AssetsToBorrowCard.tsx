// src/components/dashboard/AssetsToBorrowCard.tsx
"use client";

import {
  AssetsToBorrowCardRow,
  type BorrowAsset,
} from "./AssetsToBorrowCardRow";
import { useAaveBorrowAssets } from "@/hooks/useAaveBorrowAssets";

// symbol -> icon mapping
function getAssetIcon(symbol: string): string {
  const map: Record<string, string> = {
    AAVE: "/tokens/aave.png",
    USDC: "/tokens/usdc.png",
    WBTC: "/tokens/wbtc.png",
    LINK: "/tokens/link.png",
    DAI: "/tokens/dai.png",
    WETH: "/tokens/weth.png",
    GHO: "/tokens/gho.png",
    EURS: "/tokens/eurs.png",
    USDT: "/tokens/usdt.png",
  };
  return map[symbol] ?? "/tokens/default.png";
}

export function AssetsToBorrowCard() {
  const { rows, isLoading, isError } = useAaveBorrowAssets();

  // rows from hook → change UI  - BorrowAsset
  const borrowAssets: BorrowAsset[] = rows.map((r) => ({
    symbol: r.symbol,
    iconUrl: getAssetIcon(r.symbol),
    available: r.available,
    availableUsd: r.availableUsd ?? 0,
    // ex. hook: 79.0  → card: 0.79
    borrowApy: r.apyPercent / 100,
  }));

  return (
    <section className="mt-6 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-4">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
            <h2 className="text-sm font-semibold text-slate-900">
              Assets to borrow
            </h2>
            <span className="text-[11px] text-slate-400">
              Borrowable assets from Aave V3 (Sepolia)
            </span>
          </div>

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
                {isLoading ? (
                  <tr>
                    <td
                      colSpan={3}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      Loading borrowable assets...
                    </td>
                  </tr>
                ) : isError ? (
                  <tr>
                    <td
                      colSpan={3}
                      className="px-4 py-6 text-center text-xs text-red-500"
                    >
                      Failed to load borrowable assets
                    </td>
                  </tr>
                ) : (
                  // use borrowAssets, not rows
                  borrowAssets.map((asset) => (
                    <AssetsToBorrowCardRow key={asset.symbol} asset={asset} />
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
