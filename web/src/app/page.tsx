// src/app/page.tsx
"use client";
import { ClientOnly } from "@/components/common/ClientOnly";

import Connect from "@/components/Connect";
import { AssetsToSupplyCard } from "@/components/dashboard/AssetsToSupplyCard";
import { AssetsToBorrowCard } from "@/components/dashboard/AssetsToBorrowCard";
import { YourSupplyCard } from "@/components/dashboard/YourSupplyCard";
import { YourBorrowCard } from "@/components/dashboard/YourBorrowCard";
import { StrategyPositionCard } from "@/components/dashboard/strategy/StrategyPositionCard";
import { PositionActivitySection } from "@/components/dashboard/strategy/PositionActivitySection";
import {
  AssetOption,
  OpenPositionPreviewModal,
} from "@/components/modals/OpenPositionPreviewModal";
import { DemoTraderModal } from "@/components/modals/DemoTraderModal";
import { AllPositionsModal } from "@/components/modals/AllPositionsModal";

import { useState } from "react";
import { useAccount, useBalance } from "wagmi";
import { HookEventSection } from "@/components/dashboard/HookEventSection";

export default function Page() {
  const [isPreviewOpen, setIsPreviewOpen] = useState(false);
  const [selectedSupplySymbol, setSelectedSupplySymbol] = useState<
    string | undefined
  >(undefined);
  const [isDemoTraderOpen, setIsDemoTraderOpen] = useState(false);
  const [isAllPositionsOpen, setIsAllPositionsOpen] = useState(false);

  const { address: walletAddress, isConnected } = useAccount();
  const { data: ethBalance } = useBalance({ address: walletAddress });

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
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-xl font-semibold">Forkcast DeFi</h1>
            <p className="text-sm text-gray-500">
              Preview & run a one-shot Aave → Uniswap v4 LP strategy
            </p>
          </div>
          {isConnected && walletAddress && (
            <div className="flex flex-col items-end gap-1 rounded-xl border border-slate-700 bg-slate-800/60 px-4 py-2 text-right">
              <span className="text-xs text-slate-400">
                {walletAddress.slice(0, 6)}…{walletAddress.slice(-4)}
              </span>
              <span className="text-sm font-semibold text-slate-100">
                {ethBalance
                  ? `${parseFloat(ethBalance.formatted).toFixed(4)} ETH`
                  : "—"}
              </span>
            </div>
          )}
        </div>

        {/* Top : 왼쪽 Connect/Demo, 오른쪽 All Positions */}
        <div className="mt-6 flex items-center justify-between">
          <div className="flex gap-3">
            <Connect />
            <button
              className="border rounded px-3 py-2"
              onClick={() => setIsDemoTraderOpen(true)}
            >
              Run demo trader
            </button>
          </div>
          <button
            className="border rounded px-3 py-2 text-sm"
            onClick={() => setIsAllPositionsOpen(true)}
          >
            View all positions
          </button>
        </div>

        {/* Event Section */}
        <HookEventSection />

        <section className="mt-8">
          <StrategyPositionCard />
          <PositionActivitySection />
        </section>

        {/* Latest 2 LP Cards only */}
        <div className="mt-6 grid gap-4 lg:grid-cols-2 lg:gap-6">
          <YourSupplyCard />
          <YourBorrowCard />
        </div>

        {/* Assets to Suppy/Borrow cards */}
        <div className="mt-1 grid gap-4 lg:grid-cols-2 lg:gap-6">
          <AssetsToSupplyCard onClickPreview={handleClickPreview} />
          <AssetsToBorrowCard />
        </div>

        {/* openPosition preview modal */}
        <OpenPositionPreviewModal
          isOpen={isPreviewOpen}
          onClose={() => setIsPreviewOpen(false)}
          supplyOptions={supplyOptions}
          borrowOptions={borrowOptions}
          initialSupplySymbol={selectedSupplySymbol}
        />

        {/* demo trader modal */}
        <DemoTraderModal
          isOpen={isDemoTraderOpen}
          onClose={() => setIsDemoTraderOpen(false)}
        />

        {/* all positions modal */}
        <AllPositionsModal
          isOpen={isAllPositionsOpen}
          onClose={() => setIsAllPositionsOpen(false)}
        />
      </main>
    </ClientOnly>
  );
}
