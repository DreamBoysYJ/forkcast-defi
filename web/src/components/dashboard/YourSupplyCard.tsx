"use client";

import { YourSupplyRow, type YourSupply } from "./YourSupplyRow";

// 나중에 컨트랙트 값으로 교체할 mock 데이터
const demoSupplies: YourSupply[] = [
  {
    symbol: "AAVE",
    iconUrl: "/tokens/aave.png",
    supplied: 100,
    suppliedUsd: 3000,
    apy: 0.03,
    isCollateral: true,
  },
  {
    symbol: "USDC",
    iconUrl: "/tokens/usdc.png",
    supplied: 500,
    suppliedUsd: 500,
    apy: 0.02,
    isCollateral: true,
  },
];

export function YourSupplyCard() {
  return (
    <section className="mt-8 flex justify-center">
      <div className="w-full max-w-5xl rounded-2xl border border-slate-800/40 bg-slate-900/40 p-3">
        <div className="overflow-hidden rounded-xl bg-white shadow-sm">
          {/* 카드 헤더 */}
          <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3">
            <h2 className="text-sm font-semibold text-slate-900">
              Your supplies (demo)
            </h2>
            <span className="text-[11px] text-slate-400">
              Current supplied assets (Aave V3 style)
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
                {demoSupplies.map((item) => (
                  <YourSupplyRow key={item.symbol} item={item} />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
  );
}
