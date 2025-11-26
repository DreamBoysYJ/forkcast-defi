// src/hooks/useStrategyPositionView.ts
"use client";

import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { strategyRouterContract, strategyLensContract } from "@/lib/contracts";

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
    query: {
      enabled: !!address,
    },
    allowFailure: true,
  });

  const tokenIds: bigint[] =
    idResults
      ?.map((r) => (r?.result as bigint | undefined) ?? 0n)
      .filter((id) => id !== 0n) ?? [];

  // 토큰이 하나도 없으면 바로 종료
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
    query: {
      enabled: !!address && hasAnyToken,
    },
    allowFailure: true,
  });

  let view: StrategyPositionView | null = null;

  if (viewResults && tokenIds.length > 0) {
    // helper: raw struct → StrategyPositionView 로 매핑
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

    // 2-1) **가장 최근(open) 포지션** 찾기
    // userPositionIds(index)가 0,1,2,... 순이라면
    // tokenIds 배열도 오래된 → 최신 순서니까,
    // 뒤에서부터 스캔하면 "가장 최신 open" 을 잡을 수 있음.
    for (let i = viewResults.length - 1; i >= 0; i--) {
      const r: any = viewResults[i];
      if (!r) continue;

      const raw = r.result ?? r; // wagmi 버전에 따라 result 안/밖일 수 있음
      if (!raw || !raw.core) continue;

      if (raw.core.isOpen) {
        const tokenId = tokenIds[i];
        view = mapToView(raw, tokenId);
        break;
      }
    }

    // 2-2) open 포지션이 하나도 없으면,
    // 마지막으로 성공한 포지션(Closed) 하나라도 보여주고 싶다면 fallback
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

  return {
    view, // null이면 “No strategy position found yet”
    isLoading: isIdsLoading || isViewsLoading,
    isError: Boolean(idsError || viewsError),
  };
}
