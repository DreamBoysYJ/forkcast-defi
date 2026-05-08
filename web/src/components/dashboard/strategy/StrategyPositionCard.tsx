// components/dashboard/strategy/StrategyPositionCard.tsx
"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useAccount, useConfig } from "wagmi";
import {
  simulateContract,
  writeContract,
  waitForTransactionReceipt,
} from "@wagmi/core";
import {
  StrategyPositionRow,
  type StrategyPositionRowData,
} from "./StrategyPositionRow";
import { ClosePositionPreviewModal } from "@/components/modals/ClosePositionPreviewModal";
import { PositionSnapshotModal } from "@/components/modals/PositionSnapshotModal";
import { CollectFeesModal } from "@/components/modals/CollectFeesModal";
import type { UniPositionRowData } from "@/components/dashboard/UniswapPositionRow";
import { useStrategyPositionView } from "@/hooks/useStrategyPositionView";
import { strategyRouterContract } from "@/lib/contracts";
import { postTxHint } from "@/lib/backendApi";
import { refreshActiveQueries } from "@/lib/refreshActiveQueries";

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
  const short = `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  return { symbol: short, iconUrl: "/tokens/default.png" };
}

function toRowData(
  view: ReturnType<typeof useStrategyPositionView>["views"][number]
): StrategyPositionRowData {
  const supplyToken = getTokenMeta(view.supplyAsset);
  const borrowToken = getTokenMeta(view.borrowAsset);
  const poolToken0 = getTokenMeta(view.uniToken0);
  const poolToken1 = getTokenMeta(view.uniToken1);
  const inRange =
    view.currentTick >= view.tickLower && view.currentTick <= view.tickUpper;

  return {
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
    rangeLabel: `${view.tickLower} ~ ${view.tickUpper}`,
    currentTickLabel: `Current tick ≈ ${view.currentTick}`,
    inRange,
    totalCollateralUsd: view.totalCollateralUsd,
    totalDebtUsd: view.totalDebtUsd,
    availableBorrowUsd: view.availableBorrowUsd,
    ltv: view.ltv,
    liquidationThreshold: view.liqThreshold,
    healthFactor: view.healthFactor,
  };
}

export function StrategyPositionCard() {
  const { views, isLoading, isError, isRateLimited } = useStrategyPositionView();
  const wagmiConfig = useConfig();
  const queryClient = useQueryClient();
  const { address } = useAccount();

  // Close modal
  const [isCloseModalOpen, setIsCloseModalOpen] = useState(false);
  const [selectedTokenId, setSelectedTokenId] = useState<number | null>(null);

  // Snapshot modal
  const [isSnapshotOpen, setIsSnapshotOpen] = useState(false);
  const [snapshotTokenId, setSnapshotTokenId] = useState<number | null>(null);

  // Collect fees modal
  const [isCollectOpen, setIsCollectOpen] = useState(false);
  const [collectPosition, setCollectPosition] =
    useState<UniPositionRowData | null>(null);
  const [isCollectProcessing, setIsCollectProcessing] = useState(false);

  const rowDataList = views.filter((v) => v.tokenId !== 0n).map(toRowData);
  const hasPosition = rowDataList.length > 0;

  const selectedRowData =
    selectedTokenId !== null
      ? (rowDataList.find((r) => r.tokenId === selectedTokenId) ?? null)
      : null;

  const handlePreviewCloseClick = (tokenId: number) => {
    setSelectedTokenId(tokenId);
    setIsCloseModalOpen(true);
  };

  const handleHistoryClick = (tokenId: number) => {
    setSnapshotTokenId(tokenId);
    setIsSnapshotOpen(true);
  };

  const handleCollectClick = (tokenId: number) => {
    const row = rowDataList.find((r) => r.tokenId === tokenId);
    if (!row) return;
    setCollectPosition({
      tokenId,
      token0Symbol: row.poolToken0.symbol,
      token1Symbol: row.poolToken1.symbol,
      token0IconUrl: row.poolToken0.iconUrl ?? "/tokens/default.png",
      token1IconUrl: row.poolToken1.iconUrl ?? "/tokens/default.png",
      rangeLabel: row.rangeLabel,
      inRange: row.inRange,
      amount0NowLabel: `${row.poolToken0.symbol} ${row.amount0Now.toFixed(2)}`,
      amount1NowLabel: `${row.poolToken1.symbol} ${row.amount1Now.toFixed(2)}`,
    });
    setIsCollectOpen(true);
  };

  const handlePreviewCollect = async (): Promise<{
    amount0Label: string;
    amount1Label: string;
  }> => {
    if (!collectPosition) return { amount0Label: "0", amount1Label: "0" };
    setIsCollectProcessing(true);
    try {
      const { result } = await simulateContract(wagmiConfig, {
        ...strategyRouterContract,
        functionName: "collectFees",
        args: [BigInt(collectPosition.tokenId)],
      });
      const [raw0, raw1] = result as readonly [bigint, bigint];
      const fmt = (v: bigint) =>
        (Number(v) / 1e18).toLocaleString("en-US", {
          minimumFractionDigits: 0,
          maximumFractionDigits: 18,
        });
      return {
        amount0Label: `${collectPosition.token0Symbol} ${fmt(raw0)}`,
        amount1Label: `${collectPosition.token1Symbol} ${fmt(raw1)}`,
      };
    } finally {
      setIsCollectProcessing(false);
    }
  };

  const handleExecuteCollect = async (): Promise<void> => {
    if (!collectPosition) return;
    setIsCollectProcessing(true);
    try {
      const hash = await writeContract(wagmiConfig, {
        ...strategyRouterContract,
        functionName: "collectFees",
        args: [BigInt(collectPosition.tokenId)],
      });
      if (address) {
        postTxHint({
          txHash: hash,
          actionType: "COLLECT_FEES",
          userAddress: address,
        }).catch((err) => console.error("[tx-hint] COLLECT_FEES failed", err));
      }
      const receipt = await waitForTransactionReceipt(wagmiConfig, { hash });
      if (receipt.status === "reverted") {
        throw new Error("collectFees reverted on-chain");
      }
      await refreshActiveQueries(queryClient);
    } finally {
      setIsCollectProcessing(false);
    }
  };

  return (
    <>
      {/* Main Card */}
      <div className="rounded-2xl border border-slate-800/60 bg-slate-950/70 shadow-sm">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800/60 px-6 py-4">
          <div className="flex flex-col">
            <h2 className="text-xl font-semibold text-slate-50">
              Strategy overview
            </h2>
            <p className="text-sm text-slate-400">
              Supply → Borrow → LP on Uniswap v4
            </p>
          </div>
          <span className="text-[11px] text-slate-500">
            Strategy data – combined from Aave &amp; Uniswap v4
          </span>
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
          ) : !hasPosition ? (
            <div className="py-8 text-center text-sm text-slate-500">
              No strategy position found yet. Open a one-shot position first.
            </div>
          ) : (
            <div className="flex flex-col divide-y divide-slate-800/60">
              {rowDataList.map((rowData) => (
                <div
                  key={rowData.tokenId}
                  className="py-5 first:pt-0 last:pb-0"
                >
                  <StrategyPositionRow
                    data={rowData}
                    onClickPreviewClose={handlePreviewCloseClick}
                    onClickHistory={handleHistoryClick}
                    onClickCollect={handleCollectClick}
                  />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Close preview Modal */}
      {selectedTokenId !== null && selectedRowData && (
        <ClosePositionPreviewModal
          isOpen={isCloseModalOpen}
          onClose={() => setIsCloseModalOpen(false)}
          tokenId={selectedTokenId}
          totalDebtUsdFromCard={selectedRowData.totalDebtUsd}
        />
      )}

      {/* Snapshot history modal */}
      {snapshotTokenId !== null && (
        <PositionSnapshotModal
          isOpen={isSnapshotOpen}
          onClose={() => setIsSnapshotOpen(false)}
          tokenId={snapshotTokenId}
        />
      )}

      {/* Collect fees modal */}
      <CollectFeesModal
        isOpen={isCollectOpen}
        onClose={() => setIsCollectOpen(false)}
        position={collectPosition}
        isProcessing={isCollectProcessing}
        onPreview={handlePreviewCollect}
        onExecute={handleExecuteCollect}
      />
    </>
  );
}
