// src/hooks/useWalletTokenBalances.ts
"use client";

import { useAccount, useReadContracts } from "wagmi";
import { erc20Abi } from "@/abi/erc20Abi";

type BalanceResult = {
  asset: string; // 토큰 주소
  balance: bigint; // 원 단위 (18 or 6 decimals 그대로)
};

export function useWalletTokenBalances(assets: string[] | undefined) {
  const { address } = useAccount();

  const enabled = !!address && !!assets && assets.length > 0;

  const { data, isLoading } = useReadContracts({
    // assets.length 개 만큼 balanceOf 호출 (멀티콜)
    contracts: enabled
      ? assets.map((asset) => ({
          address: asset as `0x${string}`,
          abi: erc20Abi,
          functionName: "balanceOf",
          args: [address as `0x${string}`],
        }))
      : [],
    query: {
      enabled,
    },
  });

  const balances: BalanceResult[] =
    enabled && data
      ? data.map((res, i) => ({
          asset: assets![i],
          balance: (res?.result ?? 0n) as bigint,
        }))
      : [];

  return { balances, isLoading };
}
