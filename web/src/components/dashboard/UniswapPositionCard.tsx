// src/components/dashboard/uniswap/UniswapPositionCard.tsx
"use client";

import { useState } from "react";
import { useConfig } from "wagmi";
import {
  simulateContract,
  writeContract,
  waitForTransactionReceipt,
} from "@wagmi/core";

import {
  UniswapPositionRow,
  type UniPositionRowData,
} from "./UniswapPositionRow";
import { CollectFeesModal } from "../modals/CollectFeesModal";
import { useUserUniPositions } from "@/hooks/useUserUniPositions";
import { strategyRouterContract } from "@/lib/contracts";

// Token Metadata for LP table
const TOKEN_META: Record<
  string,
  { symbol: string; icon: string; decimals: number }
> = {
  // token0: AAVE
  "0x88541670e55cc00beefd87eb59edd1b7c511ac9a": {
    symbol: "AAVE",
    icon: "/tokens/aave.png",
    decimals: 18,
  },
  // token1: LINK
  "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5": {
    symbol: "LINK",
    icon: "/tokens/link.png",
    decimals: 18,
  },
};

function getTokenMeta(addr: `0x${string}` | undefined) {
  if (!addr) {
    return { symbol: "TOKEN", icon: "/tokens/default.png", decimals: 18 };
  }
  const found = TOKEN_META[addr.toLowerCase()];
  if (found) return found;
  return { symbol: "TOKEN", icon: "/tokens/default.png", decimals: 18 };
}

/**
 * amount: bigint (18 decs normally)
 * minFrac / maxFrac -  controls the decimal precision range
 * - LP amount: (2, 2)
 * - fees collected so far: (0, 18)
 */
function formatTokenAmount(
  amount: bigint,
  decimals: number,
  minFrac = 2,
  maxFrac = 2
): string {
  if (amount === 0n) {
    return (0).toLocaleString("en-US", {
      minimumFractionDigits: minFrac,
      maximumFractionDigits: maxFrac,
    });
  }

  const num = Number(amount) / 10 ** decimals;
  if (!Number.isFinite(num)) return "0";

  return num.toLocaleString("en-US", {
    minimumFractionDigits: minFrac,
    maximumFractionDigits: maxFrac,
  });
}

function formatTickRange(lower: number, upper: number): string {
  return `${lower.toLocaleString("en-US")} ~ ${upper.toLocaleString("en-US")}`;
}

type CollectedFees = {
  amount0Label: string;
  amount1Label: string;
};

export function UniswapPositionCard() {
  const { tokenIds, positions, isLoading, isError, isRateLimited } =
    useUserUniPositions();
  const wagmiConfig = useConfig();

  const [selectedPosition, setSelectedPosition] =
    useState<UniPositionRowData | null>(null);
  const [isCollectOpen, setIsCollectOpen] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);

  // StrategyLens raw position data → Table data
  const rows: UniPositionRowData[] =
    positions
      ?.map((pos, idx) => {
        const idBig = tokenIds?.[idx] ?? BigInt(idx);

        // amount0Now, amount1Now both 0 -> hide position from table
        const isEmptyPosition = pos.amount0Now === 0n && pos.amount1Now === 0n;
        if (isEmptyPosition) return null;

        const meta0 = getTokenMeta(pos.token0);
        const meta1 = getTokenMeta(pos.token1);

        // LP amounts(left) : 2
        const amount0Label = `${meta0.symbol} ${formatTokenAmount(
          pos.amount0Now,
          meta0.decimals,
          2,
          2
        )}`;
        const amount1Label = `${meta1.symbol} ${formatTokenAmount(
          pos.amount1Now,
          meta1.decimals,
          2,
          2
        )}`;

        const inRange =
          pos.currentTick >= pos.tickLower && pos.currentTick <= pos.tickUpper;

        return {
          tokenId: Number(idBig),
          token0Symbol: meta0.symbol,
          token1Symbol: meta1.symbol,
          token0IconUrl: meta0.icon,
          token1IconUrl: meta1.icon,
          rangeLabel: formatTickRange(pos.tickLower, pos.tickUpper),
          inRange,
          amount0NowLabel: amount0Label,
          amount1NowLabel: amount1Label,
        };
      })
      .filter((row): row is UniPositionRowData => row !== null) ?? [];

  const openCollectModal = (pos: UniPositionRowData) => {
    setSelectedPosition(pos);
    setIsCollectOpen(true);
  };

  // preview(simulation) – when click "Preview fees" in modal
  const handlePreviewCollect = async (): Promise<CollectedFees> => {
    if (!selectedPosition) {
      return {
        amount0Label: "0",
        amount1Label: "0",
      };
    }

    setIsProcessing(true);
    try {
      const tokenIdBig = BigInt(selectedPosition.tokenId);

      // 1) finds position corresponding to selectedPosition.tokenId
      const idx =
        tokenIds?.findIndex((id) => Number(id) === selectedPosition.tokenId) ??
        -1;
      const rawPos = idx >= 0 ? positions?.[idx] : undefined;

      const meta0 = rawPos ? getTokenMeta(rawPos.token0) : { decimals: 18 };
      const meta1 = rawPos ? getTokenMeta(rawPos.token1) : { decimals: 18 };

      const { result } = await simulateContract(wagmiConfig, {
        ...strategyRouterContract,
        functionName: "collectFees",
        args: [tokenIdBig],
      });

      const [raw0, raw1] = result as readonly [bigint, bigint];

      console.log("[collectFees][preview] tokenId", tokenIdBig.toString());
      console.log(
        "[collectFees][preview] raw collected0 / 1",
        raw0.toString(),
        raw1.toString()
      );

      const formatted0 = formatTokenAmount(raw0, meta0.decimals, 0, 18);
      const formatted1 = formatTokenAmount(raw1, meta1.decimals, 0, 18);

      return {
        amount0Label: `${selectedPosition.token0Symbol} ${formatted0}`,
        amount1Label: `${selectedPosition.token1Symbol} ${formatted1}`,
      };
    } finally {
      setIsProcessing(false);
    }
  };

  // 2) execute collectFees – when clicks "Collect fees" in modal
  const handleExecuteCollect = async (): Promise<void> => {
    if (!selectedPosition) return;
    setIsProcessing(true);

    try {
      const tokenIdBig = BigInt(selectedPosition.tokenId);

      const hash = await writeContract(wagmiConfig, {
        ...strategyRouterContract,
        functionName: "collectFees",
        args: [tokenIdBig],
      });

      console.log("[collectFees][execute] tx hash", hash);

      await waitForTransactionReceipt(wagmiConfig, { hash });

      // TODO : trigger refetch uni position lists if needed
    } finally {
      setIsProcessing(false);
    }
  };

  return (
    <>
      <section className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/60 px-6 pt-4 pb-3 shadow-sm">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4">
          <h2 className="text-[15px] font-semibold text-slate-50">
            Your Uniswap LP
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
              {isLoading ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-6 text-center text-xs text-slate-400"
                  >
                    Loading Uniswap v4 positions...
                  </td>
                </tr>
              ) : isRateLimited ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-6 text-center text-xs text-amber-400"
                  >
                    RPC rate limit hit while loading Uniswap positions.
                    We&#39;re retrying in the background. If this keeps
                    happening, please refresh the page or try again in a few
                    seconds.
                  </td>
                </tr>
              ) : isError ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-6 text-center text-xs text-red-500"
                  >
                    Failed to load Uniswap positions. Check your RPC settings or
                    try again.
                  </td>
                </tr>
              ) : rows.length === 0 ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-6 text-center text-xs text-slate-400"
                  >
                    No Uniswap v4 LP positions yet.
                  </td>
                </tr>
              ) : (
                rows.map((position) => (
                  <UniswapPositionRow
                    key={position.tokenId}
                    position={position}
                    onClickCollect={openCollectModal}
                  />
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>

      <CollectFeesModal
        isOpen={isCollectOpen}
        onClose={() => setIsCollectOpen(false)}
        position={selectedPosition}
        isProcessing={isProcessing}
        onPreview={handlePreviewCollect}
        onExecute={handleExecuteCollect}
      />
    </>
  );
}
