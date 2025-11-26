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
          // ✅ (user, index) 두 개 인자
          args: [address as `0x${string}`, BigInt(i)],
        })),
    allowFailure: true,
    query: {
      enabled: !!address,
    },
  });

  // wagmi 타입이 복잡해서 여기서는 any로 한 번 정리
  const idResultsAny = (idResults ?? []) as any[];

  const tokenIds: bigint[] =
    idResultsAny
      .map((r) => {
        if (!r || r.status !== "success") return null;
        const id = r.result as bigint;
        // 0인 경우는 무시
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
    },
  });

  const posResultsAny = (posResults ?? []) as any[];

  let positions: RawUniPositionOverview[] =
    posResultsAny
      .map((r, idx) => {
        if (!r || r.status !== "success" || !r.result) return null;
        // 여기서 struct 전체를 한 번에 캐스팅
        const ov = r.result as RawUniPositionOverview;
        return ov;
      })
      .filter(
        (x: RawUniPositionOverview | null): x is RawUniPositionOverview =>
          x !== null
      ) ?? [];

  const isLoading = isIdsLoading || isPosLoading;
  const isError = Boolean(idsError || posError);

  // 디버깅용
  // console.log("[useUserUniPositions] tokenIds =", tokenIds);
  // console.log("[useUserUniPositions] positions =", positions);

  return {
    tokenIds,
    positions,
    isLoading,
    isError,
  };
}
