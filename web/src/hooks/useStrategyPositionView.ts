// src/hooks/useStrategyPositionView.ts
"use client";

import { useAccount, useReadContracts } from "wagmi";
import { strategyRouterContract, strategyLensContract } from "@/lib/contracts";

// (위 파일이랑 중복인데, 귀찮으면 util로 빼도 됨)
function isRateLimitError(err: unknown): boolean {
  if (!err) return false;
  const msg = String(
    (err as any)?.shortMessage ?? (err as any)?.message ?? JSON.stringify(err)
  ).toLowerCase();

  return (
    msg.includes("429") ||
    msg.includes("too many requests") ||
    msg.includes("rate limit")
  );
}

// 프론트에서 쓰기 좋은 형태
export type StrategyPositionView = {
  tokenId: bigint;
  owner: `0x${string}`;
  vault: `0x${string}`;
  supplyAsset: `0x${string}`;
  borrowAsset: `0x${string}`;
  isOpen: boolean;

  uniToken0: `0x${string}`;
  uniToken1: `0x${string}`;
  liquidity: bigint;
  amount0Now: number;
  amount1Now: number;
  tickLower: number;
  tickUpper: number;
  currentTick: number;

  totalCollateralUsd: number;
  totalDebtUsd: number;
  availableBorrowUsd: number;
  ltv: number;
  liqThreshold: number;
  healthFactor: number;
};

export function useStrategyPositionView() {
  const { address } = useAccount();

  // 1) 이 유저의 tokenId 후보들 (최대 5개만 본다)
  const {
    data: idResults,
    isPending: isIdsLoading,
    error: idsError,
  } = useReadContracts({
    contracts: !address
      ? []
      : Array.from({ length: 20 }, (_, i) => ({
          ...strategyRouterContract,
          functionName: "userPositionIds",
          args: [address as `0x${string}`, BigInt(i)],
        })),
    allowFailure: true,
    query: {
      enabled: !!address,
      retry: (failureCount, error) => {
        if (isRateLimitError(error)) return failureCount < 5;
        return failureCount < 2;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 15_000),
      refetchOnWindowFocus: false,
      staleTime: 10_000,
    },
  });

  const tokenIds: bigint[] =
    idResults
      ?.map((r) => (r?.result as bigint | undefined) ?? 0n)
      .filter((id) => id !== 0n) ?? [];

  const hasAnyToken = tokenIds.length > 0;

  // 2) 각 tokenId마다 StrategyLens.getStrategyPositionView(tokenId) 호출
  const {
    data: viewResults,
    isPending: isViewsLoading,
    error: viewsError,
  } = useReadContracts({
    contracts: !hasAnyToken
      ? []
      : tokenIds.map((id) => ({
          ...strategyLensContract,
          functionName: "getStrategyPositionView",
          args: [id],
        })),
    allowFailure: true,
    query: {
      enabled: !!address && hasAnyToken,
      retry: (failureCount, error) => {
        if (isRateLimitError(error)) return failureCount < 5;
        return failureCount < 2;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 15_000),
      refetchOnWindowFocus: false,
      staleTime: 10_000,
    },
  });

  const mapToView = (raw: any, tokenId: bigint): StrategyPositionView => ({
    tokenId,
    owner: raw.core.owner,
    vault: raw.core.vault,
    supplyAsset: raw.core.supplyAsset,
    borrowAsset: raw.core.borrowAsset,
    isOpen: raw.core.isOpen,

    uniToken0: raw.uniToken0,
    uniToken1: raw.uniToken1,
    liquidity: raw.liquidity,
    amount0Now: Number(raw.amount0Now) / 1e18,
    amount1Now: Number(raw.amount1Now) / 1e18,
    tickLower: Number(raw.tickLower),
    tickUpper: Number(raw.tickUpper),
    currentTick: Number(raw.currentTick),

    totalCollateralUsd: Number(raw.totalCollateralBase) / 1e8,
    totalDebtUsd: Number(raw.totalDebtBase) / 1e8,
    availableBorrowUsd: Number(raw.availableBorrowBase) / 1e8,
    ltv: Number(raw.ltv) / 1e4,
    liqThreshold: Number(raw.currentLiquidationThreshold) / 1e4,
    healthFactor: raw.healthFactor >= 2n ** 128n ? Infinity : Number(raw.healthFactor) / 1e18,
  });

  // allowFailure:true 는 top-level error를 세우지 않으므로 per-item 실패를 직접 추출
  const viewItemErrors: Error[] =
    (viewResults ?? [])
      .filter((r: any) => r?.status === "failure")
      .map((r: any) => r?.error);

  if (viewItemErrors.length > 0) {
    console.error("[useStrategyPositionView] getStrategyPositionView per-item failures:", viewItemErrors);
  }

  const allViewsFailed =
    hasAnyToken &&
    viewResults !== undefined &&
    viewResults.length > 0 &&
    viewResults.every((r: any) => r?.status === "failure");

  let views: StrategyPositionView[] = [];

  if (viewResults && tokenIds.length > 0) {
    const openViews: StrategyPositionView[] = [];
    let closedFallback: StrategyPositionView | null = null;

    for (let i = 0; i < viewResults.length; i++) {
      const r: any = viewResults[i];
      if (!r) continue;
      const raw = r.result ?? r;
      if (!raw || !raw.core) continue;
      const mapped = mapToView(raw, tokenIds[i]);
      if (raw.core.isOpen) {
        openViews.push(mapped);
      } else {
        closedFallback = mapped; // 마지막 closed가 남음 (가장 최근 인덱스)
      }
    }

    views = openViews.length > 0 ? openViews : (closedFallback ? [closedFallback] : []);
  }

  const isLoading = isIdsLoading || isViewsLoading;
  const isError = Boolean(idsError || viewsError || allViewsFailed);
  const isRateLimited =
    isRateLimitError(idsError) || isRateLimitError(viewsError);

  return {
    views,
    isLoading,
    isError,
    isRateLimited,
  };
}
