"use client";

import { YourBorrowRow, type YourBorrow } from "./YourBorrowRow";

// 나중에 StrategyLens 붙이면 여기만 실제 값으로 교체
const demoBorrow: YourBorrow = {
  symbol: "WBTC",
  iconUrl: "/tokens/wbtc.png",
  debtUsd: 112.81, // 예: $112.81 빌린 상태
  borrowApy: 0.034, // 3.40%
  borrowPowerUsed: 0.006, // 0.60%
};

export function YourBorrowCard() {
  return (
    <section className="mt-8 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-3">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          {/* 카드 헤더 */}
          <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
            <h2 className="text-sm font-semibold text-slate-900">
              Your borrows (demo)
            </h2>
            <span className="text-[11px] text-slate-400">
              Debt, APY &amp; borrow power used (Aave V3 style)
            </span>
          </div>

          {/* 테이블 본문 (한 줄짜리 요약 row) */}
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
                <YourBorrowRow item={demoBorrow} />
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
