// src/hooks/usePreviewClosePosition.ts
"use client";

import { useReadContract } from "wagmi";
import { strategyRouterContract } from "@/lib/contracts";

export type PreviewClosePositionData = {
  vault: `0x${string}`;
  supplyAsset: `0x${string}`;
  borrowAsset: `0x${string}`;
  totalDebtToken: bigint; // 현재 Aave 빚 (borrowAsset 단위)
  lpBorrowTokenAmount: bigint; // LP 전량 제거 시 얻는 borrowAsset
  minExtraFromUser: bigint; // 추천 최소 추가 필요량
  maxExtraFromUser: bigint; // 이론상 최대 추가 필요량
  amount0FromLp: bigint; // LP 제거 시 받는 token0
  amount1FromLp: bigint; // LP 제거 시 받는 token1
};

function mapPreviewCloseResult(
  raw:
    | readonly [
        string,
        string,
        string,
        bigint,
        bigint,
        bigint,
        bigint,
        bigint,
        bigint
      ]
    | undefined
): PreviewClosePositionData | null {
  if (!raw) return null;

  const [
    vault,
    supplyAsset,
    borrowAsset,
    totalDebtToken,
    lpBorrowTokenAmount,
    minExtraFromUser,
    maxExtraFromUser,
    amount0FromLp,
    amount1FromLp,
  ] = raw;

  return {
    vault: vault as `0x${string}`,
    supplyAsset: supplyAsset as `0x${string}`,
    borrowAsset: borrowAsset as `0x${string}`,
    totalDebtToken,
    lpBorrowTokenAmount,
    minExtraFromUser,
    maxExtraFromUser,
    amount0FromLp,
    amount1FromLp,
  };
}

/**
 * StrategyRouter.previewClosePosition(tokenId) 뷰를 불러오는 훅
 *
 * - tokenId: 카드에서 쓰는 number 그대로 넘겨도 됨
 * - data: bigInt / address 그대로 리턴 (포맷은 컴포넌트에서)
 */
export function usePreviewClosePosition(tokenId?: number | null) {
  const enabled = typeof tokenId === "number" && tokenId > 0;

  const { data, isLoading, isError, refetch, error } = useReadContract({
    ...strategyRouterContract,
    functionName: "previewClosePosition",
    args: enabled ? [BigInt(tokenId)] : undefined,
    // wagmi v2
    query: {
      enabled,
    },
  });

  const mapped = mapPreviewCloseResult(
    data as
      | readonly [
          string,
          string,
          string,
          bigint,
          bigint,
          bigint,
          bigint,
          bigint,
          bigint
        ]
      | undefined
  );

  return {
    data: mapped, // PreviewClosePositionData | null
    isLoading,
    isError,
    error,
    refetch,
  };
}
