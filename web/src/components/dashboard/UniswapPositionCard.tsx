// components/dashboard/uniswap/UniswapPositionCard.tsx
"use client";

import { useState } from "react";
import {
  UniswapPositionRow,
  type UniPositionRowData,
} from "./UniswapPositionRow";
import { CollectFeesModal } from "../modals/CollectFeesModal";

const mockPositions: UniPositionRowData[] = [
  {
    tokenId: 1,
    token0Symbol: "AAVE",
    token1Symbol: "WBTC",
    token0IconUrl: "/tokens/aave.png",
    token1IconUrl: "/tokens/wbtc.png",
    rangeLabel: "1,500 – 2,500",
    inRange: true,
    amount0NowLabel: "AAVE 100.0000",
    amount1NowLabel: "WBTC 0.3000",
  },
  {
    tokenId: 2,
    token0Symbol: "AAVE",
    token1Symbol: "WBTC",
    token0IconUrl: "/tokens/aave.png",
    token1IconUrl: "/tokens/wbtc.png",
    rangeLabel: "2,500 – 3,500",
    inRange: false,
    amount0NowLabel: "AAVE 50.0000",
    amount1NowLabel: "WBTC 0.1000",
  },
];

export function UniswapPositionCard() {
  const [positions] = useState<UniPositionRowData[]>(mockPositions);
  const [selectedPosition, setSelectedPosition] =
    useState<UniPositionRowData | null>(null);
  const [isCollectOpen, setIsCollectOpen] = useState(false);
  const [isCollecting, setIsCollecting] = useState(false);

  const openCollectModal = (pos: UniPositionRowData) => {
    setSelectedPosition(pos);
    setIsCollectOpen(true);
  };

  const handleConfirmCollect = async () => {
    if (!selectedPosition) return;
    setIsCollecting(true);
    try {
      // TODO: 여기서 실제 router.collectFees(tokenId) 호출
      console.log("[TODO] collectFees for tokenId", selectedPosition.tokenId);
      // 성공하면 모달 닫기
      setIsCollectOpen(false);
    } finally {
      setIsCollecting(false);
    }
  };

  return (
    <>
      <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 px-6 pt-4 pb-3 shadow-sm">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4">
          <h2 className="text-[15px] font-semibold text-slate-50">
            Your Uniswap LP (demo)
          </h2>
          <span className="text-[11px] text-slate-400">
            v4 positions – data from StrategyLens
          </span>
        </div>

        {/* Table */}
        <div className="overflow-hidden rounded-3xl border-t border-slate-800/80 bg-slate-950/40">
          <table className="w-full border-collapse">
            <thead className="bg-slate-900/70 text-[11px] uppercase tracking-wide text-slate-400">
              <tr>
                <th className="px-6 py-2 text-left font-medium">Pool</th>
                <th className="px-6 py-2 text-left font-medium">Range</th>
                <th className="px-6 py-2 text-left font-medium">Liquidity</th>
                <th className="px-6 py-2 text-left font-medium">Status</th>
                <th className="px-6 py-2 text-right font-medium">Action</th>
              </tr>
            </thead>
            <tbody className="bg-slate-900/60">
              {positions.map((position) => (
                <UniswapPositionRow
                  key={position.tokenId}
                  position={position}
                  onClickCollect={openCollectModal}
                />
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <CollectFeesModal
        isOpen={isCollectOpen}
        onClose={() => setIsCollectOpen(false)}
        position={selectedPosition}
        isProcessing={isCollecting}
        onConfirm={handleConfirmCollect}
      />
    </>
  );
}
