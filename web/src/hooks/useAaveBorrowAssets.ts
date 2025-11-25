// src/hooks/useAaveBorrowAssets.ts
"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { strategyLensContract } from "@/lib/contracts";

const RAY = 10n ** 27n;

// .env 에 넣어둔 Aave 주소들
const AAVE_DATA_PROVIDER = process.env
  .NEXT_PUBLIC_AAVE_PROTOCOL_DATA_PROVIDER as `0x${string}`;

const AAVE_ORACLE = process.env.NEXT_PUBLIC_AAVE_ORACLE as `0x${string}`;

// Aave v3 Data Provider: getReserveData
const aaveDataProviderAbi = [
  {
    type: "function",
    name: "getReserveData",
    stateMutability: "view",
    inputs: [{ name: "asset", type: "address" }],
    outputs: [
      { name: "unbacked", type: "uint256" },
      { name: "accruedToTreasuryScaled", type: "uint256" },
      { name: "totalAToken", type: "uint256" },
      { name: "totalStableDebt", type: "uint256" },
      { name: "totalVariableDebt", type: "uint256" },
      { name: "liquidityRate", type: "uint256" },
      { name: "variableBorrowRate", type: "uint256" },
      { name: "stableBorrowRate", type: "uint256" },
      { name: "averageStableBorrowRate", type: "uint256" },
      { name: "liquidityIndex", type: "uint256" },
      { name: "variableBorrowIndex", type: "uint256" },
      { name: "lastUpdateTimestamp", type: "uint40" },
    ],
  },
] as const;

// Aave Oracle: 가격 + BASE_CURRENCY_UNIT
const aaveOracleAbi = [
  {
    type: "function",
    name: "getAssetsPrices",
    stateMutability: "view",
    inputs: [{ name: "assets", type: "address[]" }],
    outputs: [{ name: "", type: "uint256[]" }],
  },
  {
    type: "function",
    name: "BASE_CURRENCY_UNIT",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// StrategyLens.getAllAaveReserves() 구조
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

// StrategyLens.getAllReserveRates() 구조
type ReserveRateData = {
  asset: `0x${string}`;
  symbol: string;
  liquidityRateRay: bigint;
  variableBorrowRateRay: bigint;
  stableBorrowRateRay: bigint;
};

// 카드에서 쓸 한 줄 데이터
export type BorrowAssetRow = {
  asset: `0x${string}`;
  symbol: string;
  available: number; // 토큰 수량
  availableUsd: number;
  apyPercent: number; // 예: 79.0
};

export function useAaveBorrowAssets() {
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

  const reserves = reservesData as ReserveStaticData[] | undefined;
  const rates = ratesData as ReserveRateData[] | undefined;

  const assets = reserves?.map((r) => r.asset) ?? [];

  // 3) 각 리저브에 대한 getReserveData(asset)
  const {
    data: reserveDataResults,
    isPending: isReserveDataLoading,
    error: reserveDataError,
  } = useReadContracts({
    contracts: assets.map((asset) => ({
      address: AAVE_DATA_PROVIDER,
      abi: aaveDataProviderAbi,
      functionName: "getReserveData",
      args: [asset],
    })),
    query: {
      enabled: assets.length > 0,
    },
  });

  // 4) 가격 + BASE_CURRENCY_UNIT
  const {
    data: oracleResults,
    isPending: isOracleLoading,
    error: oracleError,
  } = useReadContracts({
    contracts:
      assets.length === 0
        ? []
        : [
            {
              address: AAVE_ORACLE,
              abi: aaveOracleAbi,
              functionName: "getAssetsPrices",
              args: [assets],
            },
            {
              address: AAVE_ORACLE,
              abi: aaveOracleAbi,
              functionName: "BASE_CURRENCY_UNIT",
              args: [],
            },
          ],
    query: {
      enabled: assets.length > 0,
    },
  });

  const isLoading =
    isReservesLoading ||
    isRatesLoading ||
    isReserveDataLoading ||
    isOracleLoading;

  const isError =
    reservesError || ratesError || reserveDataError || oracleError;

  let rows: BorrowAssetRow[] = [];

  if (
    !isLoading &&
    !isError &&
    reserves &&
    rates &&
    reserveDataResults &&
    oracleResults
  ) {
    // 금리 맵
    const rateByAsset = new Map<string, ReserveRateData>();
    for (const r of rates) {
      rateByAsset.set(r.asset.toLowerCase(), r);
    }

    // 가격 맵
    const pricesArray =
      (oracleResults[0]?.result as readonly bigint[] | undefined) ?? [];
    const baseUnit = (oracleResults[1]?.result as bigint | undefined) ?? 0n;

    const priceByAsset = new Map<string, bigint>();
    if (pricesArray.length === assets.length) {
      for (let i = 0; i < assets.length; i++) {
        priceByAsset.set(assets[i].toLowerCase(), pricesArray[i]);
      }
    }

    rows = reserves
      // ---- 필터 조건 (borrow 카드용) ----
      // - isActive == true
      // - !isFrozen
      // - !paused
      // - borrowingEnabled == true
      .filter(
        (r) => r.isActive && !r.isFrozen && !r.paused && r.borrowingEnabled
      )
      .map((r, idx) => {
        const key = r.asset.toLowerCase();
        const rate = rateByAsset.get(key);
        const reserveTuple = reserveDataResults[idx]?.result as
          | readonly [
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              number
            ]
          | undefined;

        let available = 0;
        let availableUsd = 0;

        if (reserveTuple) {
          // getReserveData 반환값 구조에서 필요한 것만 사용
          const [, , totalAToken, totalStableDebt, totalVariableDebt] =
            reserveTuple;

          // 풀 전체 남은 유동성 (토큰 * 10^decimals 단위)
          let availableRaw = totalAToken - totalStableDebt - totalVariableDebt;
          if (availableRaw < 0n) availableRaw = 0n;

          const decimals = Number(r.decimals);

          // 토큰 수량으로 스케일링
          available =
            decimals === 0
              ? Number(availableRaw)
              : Number(availableRaw) / 10 ** decimals;

          // USD 값으로 스케일링 (대충 보기용)
          const price = priceByAsset.get(key);
          if (price && baseUnit > 0n && availableRaw > 0n) {
            availableUsd =
              (Number(availableRaw) * Number(price)) /
              (10 ** decimals * Number(baseUnit));
          }
        }

        // Borrow APY (%)
        const variableBorrowRateRay = rate?.variableBorrowRateRay ?? 0n;
        const apyPercent =
          variableBorrowRateRay === 0n
            ? 0
            : (Number(variableBorrowRateRay) / Number(RAY)) * 100;

        return {
          asset: r.asset,
          symbol: r.symbol,
          available,
          availableUsd,
          apyPercent,
        };
      })
      .filter((row) => row.available > 0);

    // 디버깅용
    // console.log("borrow rows", rows);
  }

  return {
    rows,
    isLoading,
    isError: Boolean(isError),
  };
}
