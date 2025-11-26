// src/hooks/useCollectFees.ts
"use client";

import { useCallback, useState } from "react";
import { useAccount, usePublicClient, useWalletClient } from "wagmi";
import { strategyRouterContract } from "@/lib/contracts";

export type CollectFeesResult = {
  amount0: bigint;
  amount1: bigint;
  txHash: `0x${string}`;
};

export function useCollectFees() {
  const { address } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [result, setResult] = useState<CollectFeesResult | null>(null);
  const [error, setError] = useState<Error | null>(null);

  const collectFees = useCallback(
    async (tokenId: bigint) => {
      if (!address) throw new Error("Wallet not connected");
      if (!publicClient) throw new Error("Public client not ready");
      if (!walletClient) throw new Error("Wallet client not ready");

      setIsSubmitting(true);
      setError(null);

      try {
        // 1) Simulate collectFees to get expected amounts + tx request
        const simulation = await publicClient.simulateContract({
          ...strategyRouterContract,
          functionName: "collectFees",
          args: [tokenId],
          account: address,
        });

        const [amount0, amount1] = simulation.result as readonly [
          bigint,
          bigint
        ];

        // 2) Send actual transaction using the simulated request
        const txHash = await walletClient.writeContract(simulation.request);

        const res: CollectFeesResult = { amount0, amount1, txHash };
        setResult(res);
        return res;
      } catch (err) {
        const e = err as Error;
        setError(e);
        throw e;
      } finally {
        setIsSubmitting(false);
      }
    },
    [address, publicClient, walletClient]
  );

  return {
    collectFees, // (tokenId: bigint) => Promise<CollectFeesResult>
    isSubmitting, // 버튼에 "Running..." 띄울 때 사용
    result, // { amount0, amount1, txHash } – 모달 성공 화면에 표시
    error, // 실패 시 메시지용
  };
}
