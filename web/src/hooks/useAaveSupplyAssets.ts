// src/hooks/useAaveSupplyAssets.ts
"use client";

import { useAccount, useReadContract } from "wagmi";
import { useMemo } from "react";
import { strategyLensContract } from "@/lib/contracts";
import { useWalletTokenBalances } from "./useWalletTokenBalances";

const RAY = 10n ** 27n;

type ReserveStaticData = {
  asset: `0x${string}`;
  symbol: string;
  decimals: bigint;
  ltv: bigint;
  liquidationThreshold: bigint;
  liquidationBonus: bigint;
  reserveFactor: bigint;
  usageAsCollateralEnabled: boolean;
  borrowingEnabled: boolean;
  stableBorrowRateEnabled: boolean;
  isActive: boolean;
  isFrozen: boolean;
  borrowCap: bigint;
  supplyCap: bigint;
  aToken: `0x${string}`;
  stableDebtToken: `0x${string}`;
  variableDebtToken: `0x${string}`;
  paused: boolean;
};

type ReserveRateData = {
  asset: `0x${string}`;
  symbol: string;
  liquidityRateRay: bigint;
  variableBorrowRateRay: bigint;
  stableBorrowRateRay: bigint;
};

// UserReservePosition 은 이제 이 훅에선 안 써도 됨
// type UserReservePosition = { ... }

export type SupplyAssetRow = {
  asset: `0x${string}`;
  symbol: string;
  balance: number; // 지갑 토큰 수량
  apyPercent: number; // 71.1 → 71.1 (%)
  isCollateral: boolean;
  usdValue: number;
};

type AssetPriceData = {
  asset: `0x${string}`;
  priceInBaseCurrency: bigint;
};

export function useAaveSupplyAssets() {
  const { address } = useAccount();

  // 1) 모든 리저브 메타데이터
  const {
    data: reservesData,
    isPending: isReservesLoading,
    error: reservesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAllAaveReserves",
  });

  // 2) 모든 리저브 금리
  const {
    data: ratesData,
    isPending: isRatesLoading,
    error: ratesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAllReserveRates",
  });

  const reserves = (reservesData as ReserveStaticData[]) ?? [];
  const rates = (ratesData as ReserveRateData[]) ?? [];

  // 3) 리저브 주소 배열 → 지갑 잔고 읽기
  const assetAddresses = useMemo(
    () => reserves.map((r) => r.asset as string),
    [reserves]
  );

  // 오라클 base currency & unit
  const { data: oracleBaseData } = useReadContract({
    ...strategyLensContract,
    functionName: "getOracleBaseCurrency",
  });

  const { data: pricesData, isPending: isPricesLoading } = useReadContract({
    ...strategyLensContract,
    functionName: "getAssetsPrices",
    args: assetAddresses.length
      ? [assetAddresses as `0x${string}`[]]
      : undefined,
    query: {
      enabled: assetAddresses.length > 0,
    },
  });

  const baseUnit =
    (oracleBaseData as readonly [string, bigint] | undefined)?.[1] ?? 1n;
  const prices = (pricesData as AssetPriceData[]) ?? [];

  const { balances, isLoading: isBalancesLoading } = useWalletTokenBalances(
    assetAddresses.length ? assetAddresses : undefined
  );

  const isLoading =
    isReservesLoading || isRatesLoading || isBalancesLoading || isPricesLoading;

  const isError = reservesError || ratesError;

  // 주소 → rate, balance 맵으로
  const rateByAsset = useMemo(() => {
    const map = new Map<string, ReserveRateData>();
    for (const r of rates) {
      map.set(r.asset.toLowerCase(), r);
    }
    return map;
  }, [rates]);

  const balanceByAsset = useMemo(() => {
    const map = new Map<string, bigint>();
    for (const b of balances) {
      map.set(b.asset.toLowerCase(), b.balance);
    }
    return map;
  }, [balances]);

  const priceByAsset = useMemo(() => {
    const map = new Map<string, AssetPriceData>();
    for (const p of prices) {
      map.set(p.asset.toLowerCase(), p);
    }
    return map;
  }, [prices]);

  let rows: SupplyAssetRow[] = [];

  if (!isLoading && !isError && reserves.length > 0) {
    rows = reserves
      // ---- supply 카드 필터 기준 ----
      // Aave의 "Assets to supply"와 비슷하게:
      .filter(
        (r) =>
          r.isActive && !r.isFrozen && !r.paused && r.usageAsCollateralEnabled
      )
      .map((r) => {
        const key = r.asset.toLowerCase();

        // ---- ① 지갑 토큰 수량 ----
        const balanceRaw = balanceByAsset.get(key) ?? 0n;
        const decimals = Number(r.decimals);
        const decimalsPow = 10n ** BigInt(decimals);

        const balance =
          decimals === 0
            ? Number(balanceRaw)
            : Number(balanceRaw) / 10 ** decimals;

        // ---- ② APY ----
        const rate = rateByAsset.get(key);
        const liquidityRateRay = rate?.liquidityRateRay ?? 0n;
        const apyPercent =
          liquidityRateRay === 0n
            ? 0
            : (Number(liquidityRateRay) / Number(RAY)) * 100;

        // ---- ③ 가격 & USD 값 (실제로는 base currency 기준) ----
        const priceEntry = priceByAsset.get(key);
        const priceRaw = priceEntry?.priceInBaseCurrency ?? 0n; // baseUnit 스케일

        // tokenValueRaw = balanceRaw * priceRaw / 10^decimals  (여전히 baseUnit 스케일)
        const tokenValueRaw =
          decimalsPow === 0n ? 0n : (balanceRaw * priceRaw) / decimalsPow;

        const usdValue =
          baseUnit === 0n ? 0 : Number(tokenValueRaw) / Number(baseUnit); // "달러"라고 표시하지만 실제론 Aave base currency

        return {
          asset: r.asset,
          symbol: r.symbol,
          balance,
          apyPercent,
          isCollateral: r.usageAsCollateralEnabled,
          usdValue,
        };
      });
  }

  return {
    rows,
    isLoading,
    isError: Boolean(isError),
  };
}
