// src/hooks/useUserUniPositions.ts
"use client";

import { useAccount, useReadContracts } from "wagmi";
import { strategyRouterContract, strategyLensContract } from "@/lib/contracts";

const MAX_POSITIONS = 5 as const;

// Lens.getUserUniPosition 이 돌려주는 struct 모양
export type RawUniPositionOverview = {
  token0: `0x${string}`;
  token1: `0x${string}`;
  liquidity: bigint;
  amount0Now: bigint;
  amount1Now: bigint;
  tickLower: number;
  tickUpper: number;
  currentTick: number;
  sqrtPriceX96: bigint;
};

// ⭐ 공통: 레이트 리밋 에러인지 문자열로 판별
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

export function useUserUniPositions() {
  const { address } = useAccount();

  // -------------------- 1) userPositionIds(user, index) 0~4 호출 --------------------
  const {
    data: idResults,
    isPending: isIdsLoading,
    error: idsError,
  } = useReadContracts({
    contracts: !address
      ? []
      : Array.from({ length: MAX_POSITIONS }, (_, i) => ({
          ...strategyRouterContract,
          functionName: "userPositionIds",
          args: [address as `0x${string}`, BigInt(i)],
        })),
    allowFailure: true,
    query: {
      enabled: !!address,
      // ⭐ 429 등 RPC 에러용 재시도 + 백오프
      retry: (failureCount, error) => {
        if (isRateLimitError(error)) {
          return failureCount < 5; // 최대 5번까지 재시도
        }
        return failureCount < 2; // 그 외 에러는 2번까지만
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 15_000), // 1s → 2s → 4s … 최대 15s
      refetchOnWindowFocus: false,
      staleTime: 10_000,
    },
  });

  const idResultsAny = (idResults ?? []) as any[];

  const tokenIds: bigint[] =
    idResultsAny
      .map((r) => {
        if (!r || r.status !== "success") return null;
        const id = r.result as bigint;
        if (!id || id === 0n) return null;
        return id;
      })
      .filter((x: bigint | null): x is bigint => x !== null) ?? [];

  // -------------------- 2) 각 tokenId에 대한 getUserUniPosition(user, tokenId) --------------------
  const {
    data: posResults,
    isPending: isPosLoading,
    error: posError,
  } = useReadContracts({
    contracts: !address
      ? []
      : tokenIds.map((id) => ({
          ...strategyLensContract,
          functionName: "getUserUniPosition",
          args: [address as `0x${string}`, id],
        })),
    allowFailure: true,
    query: {
      enabled: !!address && tokenIds.length > 0,
      // ⭐ 위와 동일한 재시도 정책
      retry: (failureCount, error) => {
        if (isRateLimitError(error)) {
          return failureCount < 5;
        }
        return failureCount < 2;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 15_000),
      refetchOnWindowFocus: false,
      staleTime: 10_000,
    },
  });

  const posResultsAny = (posResults ?? []) as any[];

  const positions: RawUniPositionOverview[] =
    posResultsAny
      .map((r) => {
        if (!r || r.status !== "success" || !r.result) return null;
        return r.result as RawUniPositionOverview;
      })
      .filter(
        (x: RawUniPositionOverview | null): x is RawUniPositionOverview =>
          x !== null
      ) ?? [];

  const isLoading = isIdsLoading || isPosLoading;
  const isError = Boolean(idsError || posError);

  // ⭐ 이 훅에서 "레이트 리밋이 걸린 상태인지"도 같이 리턴
  const isRateLimited =
    isRateLimitError(idsError) || isRateLimitError(posError);

  return {
    tokenIds,
    positions,
    isLoading,
    isError,
    isRateLimited, // <- 카드에서 메시지 띄우는 용도
  };
}
