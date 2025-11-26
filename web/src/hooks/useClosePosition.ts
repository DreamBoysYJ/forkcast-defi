// src/hooks/useClosePosition.ts
"use client";

import { useCallback } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { strategyRouterContract } from "@/lib/contracts";

type ClosePositionParams = {
  tokenId: number | bigint;
};

export function useClosePosition() {
  const {
    data: txHash,
    isPending, // 지갑에서 서명 중
    error: writeError,
    reset,
    writeContractAsync,
  } = useWriteContract();

  const {
    isLoading: isConfirming, // 블록에 포함 대기 중
    isSuccess: isConfirmed, // 최종 컨펌
    error: txError,
  } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const closePosition = useCallback(
    async ({
      tokenId,
    }: ClosePositionParams): Promise<`0x${string}` | undefined> => {
      const idBig = typeof tokenId === "bigint" ? tokenId : BigInt(tokenId);

      try {
        const hash = await writeContractAsync({
          ...strategyRouterContract,
          functionName: "closePosition",
          args: [idBig],
        });
        return hash;
      } catch (err) {
        // 여기서 에러는 컴포넌트 쪽에서 잡아서 토스트 띄우면 됨
        console.error("[useClosePosition] closePosition failed", err);
        throw err;
      }
    },
    [writeContractAsync]
  );

  return {
    // 메인 액션
    closePosition,

    // 상태들
    txHash,
    isPending, // 서명 중
    isConfirming, // tx mining 중
    isConfirmed, // 완료
    error: (writeError || txError) ?? undefined,
    reset, // 모달 닫을 때 상태 초기화용
  };
}
