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
      : Array.from({ length: 5 }, (_, i) => ({
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

  let view: StrategyPositionView | null = null;

  if (viewResults && tokenIds.length > 0) {
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
      healthFactor: Number(raw.healthFactor) / 1e18,
    });

    // 최신 open 포지션 우선
    for (let i = viewResults.length - 1; i >= 0; i--) {
      const r: any = viewResults[i];
      if (!r) continue;
      const raw = r.result ?? r;
      if (!raw || !raw.core) continue;
      if (raw.core.isOpen) {
        const tokenId = tokenIds[i];
        view = mapToView(raw, tokenId);
        break;
      }
    }

    // fallback: closed 라도 하나 보여주고 싶으면
    if (!view) {
      for (let i = viewResults.length - 1; i >= 0; i--) {
        const r: any = viewResults[i];
        if (!r) continue;
        const raw = r.result ?? r;
        if (!raw || !raw.core) continue;
        const tokenId = tokenIds[i];
        view = mapToView(raw, tokenId);
        break;
      }
    }
  }

  const isLoading = isIdsLoading || isViewsLoading;
  const isError = Boolean(idsError || viewsError);
  const isRateLimited =
    isRateLimitError(idsError) || isRateLimitError(viewsError); // ⭐ 추가

  return {
    view,
    isLoading,
    isError,
    isRateLimited, // <- 카드에서 "RPC rate limit" 안내 띄울 수 있음
  };
}
