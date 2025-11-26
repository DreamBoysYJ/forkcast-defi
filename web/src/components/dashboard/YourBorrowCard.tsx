// YourBorrowCard.tsx
"use client";

import { YourBorrowRow, type YourBorrow } from "./YourBorrowRow";
import { useAaveUserBorrows } from "@/hooks/useAaveUserBorrows";

// 심볼 → 아이콘 경로 매핑
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

export function YourBorrowCard() {
  const { rows, isLoading, isError } = useAaveUserBorrows();

  // 훅 결과(rows)를 Row에서 쓰는 YourBorrow 타입으로 맞춰줌
  const items: YourBorrow[] = rows.map((r) => ({
    symbol: r.symbol,
    iconUrl: getAssetIcon(r.symbol),
    debtToken: r.debtToken,
    debtUsd: r.debtUsd,
    borrowApy: r.borrowApy,
    borrowPowerUsed: r.borrowPowerUsed,
  }));

  return (
    <section className="mt-8 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-3">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          {/* 카드 헤더 */}
          <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
            <h2 className="text-sm font-semibold text-slate-900">
              Your borrows
            </h2>
            <span className="text-[11px] text-slate-400">
              Current borrowed assets (Aave V3 – Sepolia)
            </span>
          </div>

          {/* 리스트 테이블 */}
          <div className="overflow-x-auto">
            <table className="min-w-full border-collapse">
              <thead className="bg-slate-50 text-[11px] uppercase tracking-wide text-slate-400">
                <tr>
                  <th className="px-4 py-3 text-left font-medium">Asset</th>
                  <th className="px-4 py-3 text-right font-medium">Debt</th>
                  <th className="px-4 py-3 text-right font-medium">
                    Borrow APY
                  </th>
                  <th className="px-4 py-3 text-right font-medium">
                    Borrow power used
                  </th>
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      Loading your borrow positions...
                    </td>
                  </tr>
                ) : isError ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-red-500"
                    >
                      Failed to load borrow positions. Please check console /
                      RPC.
                    </td>
                  </tr>
                ) : items.length === 0 ? (
                  <tr>
                    <td
                      colSpan={4}
                      className="px-4 py-6 text-center text-xs text-slate-400"
                    >
                      No active borrows on Aave yet.
                    </td>
                  </tr>
                ) : (
                  items.map((item: YourBorrow) => (
                    <YourBorrowRow key={item.symbol} item={item} />
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
