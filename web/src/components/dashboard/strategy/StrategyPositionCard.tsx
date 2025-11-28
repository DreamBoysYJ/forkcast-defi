// components/dashboard/strategy/StrategyPositionCard.tsx
"use client";

import { useState } from "react";
import {
  StrategyPositionRow,
  type StrategyPositionRowData,
} from "./StrategyPositionRow";
import { ClosePositionPreviewModal } from "@/components/modals/ClosePositionPreviewModal";
import { useStrategyPositionView } from "@/hooks/useStrategyPositionView";

// address -> symbol/icon mapping (.env based)
const TOKEN_META: Record<string, { symbol: string; iconUrl: string }> = {
  [(process.env.NEXT_PUBLIC_AAVE_UNDERLYING_SEPOLIA ?? "").toLowerCase()]: {
    symbol: "AAVE",
    iconUrl: "/tokens/aave.png",
  },
  [(process.env.NEXT_PUBLIC_LINK_UNDERLYING_SEPOLIA ?? "").toLowerCase()]: {
    symbol: "LINK",
    iconUrl: "/tokens/link.png",
  },
  [(process.env.NEXT_PUBLIC_WBTC_UNDERLYING_SEPOLIA ?? "").toLowerCase()]: {
    symbol: "WBTC",
    iconUrl: "/tokens/wbtc.png",
  },
};

function getTokenMeta(addr: `0x${string}`) {
  const key = addr.toLowerCase();
  const meta = TOKEN_META[key];

  if (meta) return meta;

  // fallback: show sliced address
  const short = `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  return {
    symbol: short,
    iconUrl: "/tokens/default.png",
  };
}

export function StrategyPositionCard() {
  // 1) Onchain total View Hook
  const { view, isLoading, isError, isRateLimited } = useStrategyPositionView();

  // 2) Close preview Modal State
  const [isCloseModalOpen, setIsCloseModalOpen] = useState(false);
  const [selectedTokenId, setSelectedTokenId] = useState<number | null>(null);

  const handlePreviewCloseClick = (tokenId: number) => {
    setSelectedTokenId(tokenId);
    setIsCloseModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsCloseModalOpen(false);
  };

  // 3) Onchain view → Change Row - StrategyPositionRowData
  let rowData: StrategyPositionRowData | null = null;

  if (view && view.tokenId !== 0n) {
    // !isOpen == null
    const isEffectivelyClosed =
      !view.isOpen ||
      (view.totalCollateralUsd === 0 && view.totalDebtUsd === 0);

    if (!isEffectivelyClosed) {
      const supplyToken = getTokenMeta(view.supplyAsset);
      const borrowToken = getTokenMeta(view.borrowAsset);
      const poolToken0 = getTokenMeta(view.uniToken0);
      const poolToken1 = getTokenMeta(view.uniToken1);

      const inRange =
        view.currentTick >= view.tickLower &&
        view.currentTick <= view.tickUpper;

      const rangeLabel = `${view.tickLower} ~ ${view.tickUpper}`;
      const currentTickLabel = `Current tick ≈ ${view.currentTick}`;

      rowData = {
        tokenId: Number(view.tokenId),
        isOpen: view.isOpen,

        supplyToken,
        borrowToken,
        owner: view.owner,
        vault: view.vault,

        poolToken0,
        poolToken1,
        amount0Now: view.amount0Now,
        amount1Now: view.amount1Now,
        rangeLabel,
        currentTickLabel,
        inRange,

        totalCollateralUsd: view.totalCollateralUsd,
        totalDebtUsd: view.totalDebtUsd,
        availableBorrowUsd: view.availableBorrowUsd,
        ltv: view.ltv,
        liquidationThreshold: view.liqThreshold,
        healthFactor: view.healthFactor,
      };
    }
  }

  const hasPosition = !!rowData && rowData.tokenId !== 0;
  const isOpen = rowData?.isOpen ?? false;

  return (
    <>
      {/* Main Card */}
      <div className="rounded-2xl border border-slate-800/60 bg-slate-950/70 shadow-sm">
        {/* Header*/}
        <div className="flex items-center justify-between border-b border-slate-800/60 px-6 py-4">
          <div className="flex flex-col">
            <h2 className="text-xl font-semibold text-slate-50">
              Strategy overview
            </h2>
            <p className="text-sm text-slate-400">
              Supply → Borrow → LP on Uniswap v4
            </p>
          </div>

          <div className="flex items-center gap-3">
            {hasPosition && (
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium ${
                  isOpen
                    ? "bg-emerald-500/10 text-emerald-300"
                    : "bg-slate-700/40 text-slate-300"
                }`}
              >
                <span
                  className={`h-1.5 w-1.5 rounded-full ${
                    isOpen ? "bg-emerald-400" : "bg-slate-400"
                  }`}
                />
                {isOpen ? "Open" : "Closed"}
              </span>
            )}

            <span className="text-[11px] text-slate-500">
              Strategy data – combined from Aave &amp; Uniswap v4
            </span>
          </div>
        </div>

        {/* Body */}
        <div className="px-6 py-5">
          {isLoading ? (
            <div className="py-8 text-center text-sm text-slate-500">
              Loading strategy position...
            </div>
          ) : isRateLimited ? (
            <div className="py-8 text-center text-sm text-amber-400">
              RPC rate limit hit while loading your strategy position.
              We&apos;re retrying in the background. If this keeps happening,
              please refresh the page or try again in a few seconds.
            </div>
          ) : isError ? (
            <div className="py-8 text-center text-sm text-red-400">
              Failed to load strategy position. Check your RPC settings or
              wallet connection.
            </div>
          ) : !rowData ? (
            <div className="py-8 text-center text-sm text-slate-500">
              No strategy position found yet. Open a one-shot position first.
            </div>
          ) : (
            <StrategyPositionRow
              data={rowData}
              onClickPreviewClose={handlePreviewCloseClick}
            />
          )}
        </div>
      </div>

      {/* Close preview Modal */}
      {selectedTokenId !== null && rowData && (
        <ClosePositionPreviewModal
          isOpen={isCloseModalOpen}
          onClose={handleCloseModal}
          tokenId={selectedTokenId}
          totalDebtUsdFromCard={rowData.totalDebtUsd}
        />
      )}
    </>
  );
}
