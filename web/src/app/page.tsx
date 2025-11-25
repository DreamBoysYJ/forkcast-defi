"use client";

import Connect from "@/components/Connect";
import { AssetsToSupplyCard } from "@/components/dashboard/AssetsToSupplyCard";
import { AssetsToBorrowCard } from "@/components/dashboard/AssetsToBorrowCard";
import { YourSupplyCard } from "@/components/dashboard/YourSupplyCard";
import { YourBorrowCard } from "@/components/dashboard/YourBorrowCard";
import { UniswapPositionCard } from "@/components/dashboard/UniswapPositionCard";
import { StrategyPositionCard } from "@/components/dashboard/strategy/StrategyPositionCard";
import type { StrategyPositionRowData } from "@/components/dashboard/strategy/StrategyPositionRow";
import {
  AssetOption,
  OpenPositionPreviewModal,
} from "@/components/modals/OpenPositionPreviewModal";

import { DemoTraderModal } from "@/components/modals/DemoTraderModal";

import { useState } from "react";

const mockStrategyPosition: StrategyPositionRowData = {
  tokenId: 1,
  isOpen: true,

  // 전략 구성
  supplyToken: {
    symbol: "AAVE",
    iconUrl: "/tokens/aave.png",
  },
  borrowToken: {
    symbol: "WBTC",
    iconUrl: "/tokens/wbtc.png",
  },
  owner: "0x1234567890abcdef1234567890abcdef12345678",
  vault: "0xabcdef1234567890abcdef1234567890abcdef12",

  // Uni v4 상태
  poolToken0: {
    symbol: "AAVE",
    iconUrl: "/tokens/aave.png",
  },
  poolToken1: {
    symbol: "WBTC",
    iconUrl: "/tokens/wbtc.png",
  },
  amount0Now: 100, // 숫자
  amount1Now: 0.3, // 숫자
  rangeLabel: "1,500 – 2,500",
  currentTickLabel: "Current tick ≈ 1,800",
  inRange: true,

  // Aave 리스크 (숫자, USD는 프론트에서 포맷)
  totalCollateralUsd: 3000,
  totalDebtUsd: 1120,
  availableBorrowUsd: 500,
  ltv: 0.37, // 37%
  liquidationThreshold: 0.72, // 72%
  healthFactor: 1.42,
};

export default function Page() {
  const [isPreviewOpen, setIsPreviewOpen] = useState(false);
  const [selectedSupplySymbol, setSelectedSupplySymbol] = useState<
    string | undefined
  >(undefined);
  const [isDemoTraderOpen, setIsDemoTraderOpen] = useState(false);

  const supplyOptions: AssetOption[] = [
    {
      symbol: "AAVE",
      address: process.env.NEXT_PUBLIC_AAVE_UNDERLYING_SEPOLIA as `0x${string}`,
    },
  ];

  const borrowOptions: AssetOption[] = [
    {
      symbol: "LINK",
      address: process.env.NEXT_PUBLIC_LINK_UNDERLYING_SEPOLIA as `0x${string}`,
    },
  ];

  const handleClickPreview = (symbol: string) => {
    setSelectedSupplySymbol(symbol);
    setIsPreviewOpen(true);
  };

  const handlePreviewClose = (tokenId: number) => {
    // 나중에 끝내기 프리뷰 모달 열 때 여기서 처리
    console.log("Preview close for strategy token", tokenId);
  };
  return (
    <main className="min-h-screen bg-slate-900 text-white p-6">
      <h1 className="text-xl font-semibold">Forkcast Demo</h1>
      <p className="text-sm text-gray-500">
        Aave ↔ Uniswap v4 one-shot + demo volume
      </p>
      <div className="mt-6 flex gap-3">
        <Connect />
        <button
          className="border rounded px-3 py-2"
          onClick={() => setIsDemoTraderOpen(true)}
        >
          Run demo trader
        </button>
      </div>

      <section className="mt-8">
        <StrategyPositionCard
          data={mockStrategyPosition}
          onClickPreviewClose={handlePreviewClose}
        />
      </section>

      <UniswapPositionCard />

      {/* 위쪽 2개 카드 */}
      <div className="mt-6 grid gap-4 lg:grid-cols-2 lg:gap-6">
        <YourSupplyCard />
        <YourBorrowCard />
      </div>

      {/* 아래쪽 2개 카드 */}
      <div className="mt-1 grid gap-4 lg:grid-cols-2 lg:gap-6">
        <AssetsToSupplyCard onClickPreview={handleClickPreview} />
        <AssetsToBorrowCard />
      </div>

      {/* 모달 */}
      <OpenPositionPreviewModal
        isOpen={isPreviewOpen}
        onClose={() => setIsPreviewOpen(false)}
        supplyOptions={supplyOptions}
        borrowOptions={borrowOptions}
        initialSupplySymbol={selectedSupplySymbol}
      />

      {/* demo trader 모달 */}
      <DemoTraderModal
        isOpen={isDemoTraderOpen}
        onClose={() => setIsDemoTraderOpen(false)}
      />
    </main>
  );
}
