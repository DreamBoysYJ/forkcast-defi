"use client";

import {
  AssetsToSupplyCardRow,
  type SupplyAsset,
} from "./AssetsToSupplyCardRow";
import { useAaveSupplyAssets } from "@/hooks/useAaveSupplyAssets";

type Props = {
  onClickPreview?: (symbol: string) => void;
};

// 심볼 → 아이콘 매핑 (필요한 만큼만 추가)
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
  // 1) Lens에서 데이터 읽어오기
  const { rows, isLoading, isError } = useAaveSupplyAssets();

  // 2) useAaveSupplyAssets에서 받은 rows → 기존 SupplyAsset 타입으로 변환
  const assets: SupplyAsset[] = rows.map((r) => ({
    symbol: r.symbol,
    iconUrl: ICON_MAP[r.symbol] ?? "/tokens/default.png",
    supplied: r.balance, // 토큰 수량
    suppliedUsd: r.usdValue, // TODO: 나중에 오라클 붙여서 달러로 계산
    apy: r.apyPercent / 100, // 3.0% → 0.03 형태로 맞추기
    canBeCollateral: r.isCollateral,
    // 전략에 쓰는 자산만 true로 표시하고 싶으면 조건 넣기
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
