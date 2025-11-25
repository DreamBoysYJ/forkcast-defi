// src/components/YourSupplyCard.tsx
"use client";

import { YourSupplyRow, type YourSupply } from "./YourSupplyRow";
import { useAaveUserSupplies } from "@/hooks/useAaveUserSupplies";

// 심볼 → 아이콘 경로 매핑
function getAssetIcon(symbol: string): string {
  const map: Record<string, string> = {
    AAVE: "/tokens/aave.png",
    USDC: "/tokens/usdc.png",
    USDT: "/tokens/usdt.png",
    DAI: "/tokens/dai.png",
    EURS: "/tokens/eurs.png",
    WBTC: "/tokens/wbtc.png",
    WETH: "/tokens/weth.png",
    LINK: "/tokens/link.png",
    GHO: "/tokens/gho.png",
  };
  return map[symbol] ?? "/tokens/default.png";
}

export function YourSupplyCard() {
  const { rows, isLoading, isError } = useAaveUserSupplies();

  const supplies: YourSupply[] = rows.map((r) => ({
    symbol: r.symbol,
    iconUrl: getAssetIcon(r.symbol),
    supplied: r.supplied,
    suppliedUsd: r.suppliedUsd,
    apy: r.apy,
    isCollateral: r.isCollateral,
  }));

  return (
    <section className="mt-8 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-3">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          {/* 카드 헤더 */}
          <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
            <h2 className="text-sm font-semibold text-slate-900">
              Your supplies
            </h2>
            <span className="text-[11px] text-slate-400">
              Current supplied assets (Aave V3, Sepolia vault)
            </span>
          </div>

          {/* 리스트 테이블 */}
          <div className="overflow-x-auto">
            <table className="min-w-full border-collapse">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Asset</th>
                  <th className="px-4 py-3 text-right font-medium">Balance</th>
                  <th className="px-4 py-3 text-right font-medium">APY</th>
                  <th className="px-4 py-3 text-right font-medium">Collat</th>
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      Loading your supplies...
                    </td>
                  </tr>
                ) : isError ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-red-500"
                    >
                      Failed to load your supplies.
                    </td>
                  </tr>
                ) : supplies.length === 0 ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      No supplied assets yet. Supply from the list above to see
                      them here.
                    </td>
                  </tr>
                ) : (
                  supplies.map((item) => (
                    <YourSupplyRow key={item.symbol} item={item} />
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
