// src/hooks/useAaveUserSupplies.ts
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

export type UserSupplyRow = {
  asset: `0x${string}`;
  symbol: string;
  supplied: number; // 토큰 수량
  suppliedUsd: number; // USD 가치
  apy: number; // 0.03 => 3.0%
  isCollateral: boolean;
};

export function useAaveUserSupplies() {
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

  // 2) 전체 리저브 금리
  const {
    data: ratesData,
    isPending: isRatesLoading,
    error: ratesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAllReserveRates",
  });

  // 3) 유저의 전체 리저브 포지션 (vault 기준)
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

  // 4) 오라클 base 통화/단위
  const {
    data: oracleBaseData,
    isPending: isOracleLoading,
    error: oracleError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getOracleBaseCurrency",
  });

  // 5) 자산 가격 (리저브 목록 기반)
  const assetsForPrice: `0x${string}`[] | undefined = reservesData
    ? (reservesData as ReserveStaticData[]).map((r) => r.asset)
    : undefined;

  const {
    data: pricesData,
    isPending: isPricesLoading,
    error: pricesError,
  } = useReadContract({
    ...strategyLensContract,
    functionName: "getAssetsPrices",
    args: assetsForPrice ? [assetsForPrice] : undefined,
    query: {
      enabled: Boolean(assetsForPrice),
    },
  });

  const isLoading =
    isReservesLoading ||
    isRatesLoading ||
    (address && isPositionsLoading) ||
    isOracleLoading ||
    isPricesLoading;

  const isError =
    reservesError || ratesError || positionsError || oracleError || pricesError;

  let rows: UserSupplyRow[] = [];

  if (
    !isLoading &&
    !isError &&
    reservesData &&
    ratesData &&
    positionsData &&
    oracleBaseData
  ) {
    const reserves = reservesData as ReserveStaticData[];
    const rates = ratesData as ReserveRateData[];
    const positions = positionsData as UserReservePosition[];
    const prices = (pricesData as AssetPriceData[]) || [];

    const baseUnit = (oracleBaseData as readonly [`0x${string}`, bigint])[1];

    // asset 주소 기준 맵들 생성
    const rateByAsset = new Map<string, ReserveRateData>();
    for (const r of rates) {
      rateByAsset.set(r.asset.toLowerCase(), r);
    }

    const posByAsset = new Map<string, UserReservePosition>();
    for (const p of positions) {
      posByAsset.set(p.asset.toLowerCase(), p);
    }

    const priceByAsset = new Map<string, AssetPriceData>();
    for (const p of prices) {
      priceByAsset.set(p.asset.toLowerCase(), p);
    }

    rows = reserves
      // Aave 상에서 살아 있고(frozen/paused 아님) 콜랫 가능인 리저브만
      .filter(
        (r) =>
          r.isActive && !r.isFrozen && !r.paused && r.usageAsCollateralEnabled
      )
      .map<UserSupplyRow | null>((r) => {
        const key = r.asset.toLowerCase();

        const pos = posByAsset.get(key);
        const rate = rateByAsset.get(key);
        const price = priceByAsset.get(key);

        const balanceRaw = pos?.aTokenBalance ?? 0n;
        const decimals = Number(r.decimals);

        const supplied =
          decimals === 0
            ? Number(balanceRaw)
            : Number(balanceRaw) / 10 ** decimals;

        // 아주 작은 잔고(먼지)면 카드에서 숨기고 싶으니까 여기서 컷
        if (supplied <= 0) {
          return null;
        }

        const priceRaw = price?.priceInBaseCurrency ?? 0n;
        const baseUnitNum = Number(baseUnit || 1n);

        const suppliedUsd =
          baseUnitNum === 0 ? 0 : (Number(priceRaw) / baseUnitNum) * supplied;

        const liquidityRateRay = rate?.liquidityRateRay ?? 0n;
        // apy: 0.03 => 3%
        const apy =
          liquidityRateRay === 0n ? 0 : Number(liquidityRateRay) / Number(RAY);

        return {
          asset: r.asset,
          symbol: r.symbol,
          supplied,
          suppliedUsd,
          apy,
          isCollateral: r.usageAsCollateralEnabled,
        };
      })
      .filter((row): row is UserSupplyRow => row !== null);
  }

  return {
    rows,
    isLoading,
    isError: Boolean(isError),
  };
}
