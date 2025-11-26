// src/hooks/useAaveUserBorrows.ts
"use client";

import { useAccount, useReadContract } from "wagmi";
import { strategyLensContract } from "@/lib/contracts";

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

type UserReservePosition = {
  asset: `0x${string}`;
  aTokenBalance: bigint;
  stableDebt: bigint;
  variableDebt: bigint;
};

type AssetPriceData = {
  asset: `0x${string}`;
  priceInBaseCurrency: bigint;
};

type UserAaveOverview = {
  user: `0x${string}`;
  vault: `0x${string}`;
  totalCollateralBase: bigint;
  totalDebtBase: bigint;
  availableBorrowBase: bigint;
  currentLiquidationThreshold: bigint;
  ltv: bigint;
  healthFactor: bigint;
};

// YourBorrowRow에서 쓰는 타입 형태랑 맞춰줌
export type YourBorrowRowData = {
  symbol: string;
  debtToken: number; // ✅ 새로 추가 (예: 325.0 LINK)

  debtUsd: number; // 표에 찍히는 USD
  borrowApy: number; // 0.05 → 5%
  borrowPowerUsed: number; // 0.006 → 0.6%
};

function bnToDecimal(amount: bigint, decimals: number): number {
  if (decimals === 0) return Number(amount);
  return Number(amount) / 10 ** decimals;
}

export function useAaveUserBorrows() {
  const { address } = useAccount();

  // 1) 전체 리저브 메타데이터
  const {
    data: reservesData,
    isPending: isReservesLoading,
    error: reservesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAllAaveReserves",
  });

  const reserves = (reservesData as ReserveStaticData[] | undefined) ?? [];
  const assetsForPrices = reserves.map((r) => r.asset);

  // 2) 전체 리저브 금리
  const {
    data: ratesData,
    isPending: isRatesLoading,
    error: ratesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAllReserveRates",
  });

  // 3) 유저 리저브 포지션 (vault 기준, 우리가 EOA를 넘기면 Lens가 vault 찾아줌)
  const {
    data: positionsData,
    isPending: isPositionsLoading,
    error: positionsError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getUserReservePositionsAll",
    args: address ? [address] : undefined,
    query: {
      enabled: Boolean(address),
    },
  });

  // 4) 모든 자산 가격
  const {
    data: pricesData,
    isPending: isPricesLoading,
    error: pricesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAssetsPrices",
    args: [assetsForPrices],
    query: {
      enabled: assetsForPrices.length > 0,
    },
  });

  // 5) 오라클 기준 통화 (baseUnit)
  const {
    data: oracleBaseData,
    isPending: isBaseLoading,
    error: baseError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getOracleBaseCurrency",
  });

  // 6) 유저 전체 Aave 개요 (Borrow power used 계산용)
  const {
    data: overviewData,
    isPending: isOverviewLoading,
    error: overviewError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getUserAaveOverview",
    args: address ? [address] : undefined,
    query: {
      enabled: Boolean(address),
    },
  });

  const isLoading =
    isReservesLoading ||
    isRatesLoading ||
    (address && isPositionsLoading) ||
    isPricesLoading ||
    isBaseLoading ||
    (address && isOverviewLoading);

  const isError =
    reservesError ||
    ratesError ||
    positionsError ||
    pricesError ||
    baseError ||
    overviewError;

  const rows: YourBorrowRowData[] = [];

  if (!isLoading && !isError && reservesData && ratesData && positionsData) {
    const reservesArr = reservesData as ReserveStaticData[];
    const ratesArr = ratesData as ReserveRateData[];
    const positionsArr = positionsData as UserReservePosition[];
    const pricesArr = (pricesData as AssetPriceData[] | undefined) ?? [];

    // 맵들 구성
    const reserveByAsset = new Map<string, ReserveStaticData>();
    for (const r of reservesArr) {
      reserveByAsset.set(r.asset.toLowerCase(), r);
    }

    const rateByAsset = new Map<string, ReserveRateData>();
    for (const r of ratesArr) {
      rateByAsset.set(r.asset.toLowerCase(), r);
    }

    const priceByAsset = new Map<string, AssetPriceData>();
    for (const p of pricesArr) {
      priceByAsset.set(p.asset.toLowerCase(), p);
    }

    const baseUnit =
      oracleBaseData && Array.isArray(oracleBaseData)
        ? (oracleBaseData[1] as bigint) || 1n
        : 1n;

    const overview = overviewData as UserAaveOverview | undefined;
    let borrowPowerUsed = 0;

    if (overview) {
      const totalDebtBase = overview.totalDebtBase;
      const availableBorrowBase = overview.availableBorrowBase;
      const denom = totalDebtBase + availableBorrowBase;
      if (denom > 0n) {
        borrowPowerUsed = Number(totalDebtBase) / Number(denom); // 0~1
      }
    }

    // 유저가 실제로 부채를 가진 자산만 골라서 rows 생성
    for (const pos of positionsArr) {
      const totalDebtRaw = pos.stableDebt + pos.variableDebt;
      if (totalDebtRaw === 0n) continue; // 빚 없으면 스킵

      const key = pos.asset.toLowerCase();
      const reserve = reserveByAsset.get(key);
      if (!reserve) continue;

      const rate = rateByAsset.get(key);
      const priceInfo = priceByAsset.get(key);

      const decimals = Number(reserve.decimals);
      const debtToken = bnToDecimal(totalDebtRaw, decimals);

      // 가격 (base currency → 대충 USD라고 생각)
      const priceInBase =
        baseUnit > 0n && priceInfo
          ? Number(priceInfo.priceInBaseCurrency) / Number(baseUnit)
          : 0;

      const debtUsd = debtToken * priceInBase;

      // 대출 APY (변동 금리 기준)
      const variableBorrowRateRay = rate?.variableBorrowRateRay ?? 0n;
      const borrowApyPercent =
        variableBorrowRateRay === 0n
          ? 0
          : (Number(variableBorrowRateRay) / Number(RAY)) * 100;
      const borrowApy = borrowApyPercent / 100; // 0.05 => 5%

      rows.push({
        symbol: reserve.symbol,
        debtToken,
        debtUsd,
        borrowApy,
        borrowPowerUsed,
      });
    }
  }

  return {
    rows,
    isLoading,
    isError: Boolean(isError),
  };
}
