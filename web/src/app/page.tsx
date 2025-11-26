// src/app/page.tsx
"use client";
import { ClientOnly } from "@/components/common/ClientOnly";

import Connect from "@/components/Connect";
import { AssetsToSupplyCard } from "@/components/dashboard/AssetsToSupplyCard";
import { AssetsToBorrowCard } from "@/components/dashboard/AssetsToBorrowCard";
import { YourSupplyCard } from "@/components/dashboard/YourSupplyCard";
import { YourBorrowCard } from "@/components/dashboard/YourBorrowCard";
import { UniswapPositionCard } from "@/components/dashboard/UniswapPositionCard";
import { StrategyPositionCard } from "@/components/dashboard/strategy/StrategyPositionCard";
import {
  AssetOption,
  OpenPositionPreviewModal,
} from "@/components/modals/OpenPositionPreviewModal";
import { DemoTraderModal } from "@/components/modals/DemoTraderModal";

import { useState } from "react";

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

  return (
    <ClientOnly>
      {" "}
      <main className="min-h-screen bg-slate-900 text-white p-6">
        <h1 className="text-xl font-semibold">Forkcast Demo</h1>
        <p className="text-sm text-gray-500">
          Aave ↔ Uniswap v4 one-shot + demo volume
        </p>

        {/* 상단: 지갑 연결 + 데모 트레이더 버튼 */}
        <div className="mt-6 flex gap-3">
          <Connect />
          <button
            className="border rounded px-3 py-2"
            onClick={() => setIsDemoTraderOpen(true)}
          >
            Run demo trader
          </button>
        </div>

        {/* 전략 통합 카드 (온체인 데이터로 렌더링) */}
        <section className="mt-8">
          <StrategyPositionCard />
        </section>

        {/* Uniswap LP 카드 */}
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

        {/* openPosition 프리뷰 모달 */}
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
    </ClientOnly>
  );
}
