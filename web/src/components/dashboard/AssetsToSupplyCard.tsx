"use client";

import {
  AssetsToSupplyCardRow,
  type SupplyAsset,
} from "./AssetsToSupplyCardRow";
import { useAaveSupplyAssets } from "@/hooks/useAaveSupplyAssets";

type Props = {
  onClickPreview?: (symbol: string) => void;
};

// symbol -> icon mapping
const ICON_MAP: Record<string, string> = {
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

export function AssetsToSupplyCard({ onClickPreview }: Props) {
  // 1) read data from Lens
  const { rows, isLoading, isError } = useAaveSupplyAssets();

  // 2) useAaveSupplyAssets : rows → SupplyAsset type
  const assets: SupplyAsset[] = rows.map((r) => ({
    symbol: r.symbol,
    iconUrl: ICON_MAP[r.symbol] ?? "/tokens/default.png",
    supplied: r.balance, // tokenAmount
    suppliedUsd: r.usdValue,
    apy: r.apyPercent / 100, // 3.0% → 0.03
    canBeCollateral: r.isCollateral,
    // only AAVE is available now
    // TODO : every assets could be true
    isStrategyAsset: r.symbol === "AAVE",
  }));

  return (
    <section className="mt-10 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-4">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          <div className="flex items-center justify-between border-b border-slate-100 px-6 py-4">
            <h2 className="text-sm font-semibold text-slate-900">
              Assets to supply
            </h2>
            <span className="text-[11px] text-slate-400">
              Live data (Aave V3)
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
                {isLoading && (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      Loading Aave reserves...
                    </td>
                  </tr>
                )}

                {isError && !isLoading && (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-4 py-6 text-center text-xs text-red-500"
                    >
                      Failed to load Aave data
                    </td>
                  </tr>
                )}

                {!isLoading && !isError && assets.length === 0 && (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      No supplyable assets found on Aave.
                    </td>
                  </tr>
                )}

                {!isLoading &&
                  !isError &&
                  assets.map((asset) => (
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
