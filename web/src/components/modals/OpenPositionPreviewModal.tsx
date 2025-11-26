"use client";

import { useEffect, useState } from "react";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useWriteContract,
} from "wagmi";
import { erc20Abi, parseUnits } from "viem";
import { strategyRouterContract, strategyLensContract } from "@/lib/contracts";
import { useRouter } from "next/navigation";

export type AssetOption = {
  symbol: string;
  address: `0x${string}`;
};

type OpenPositionPreviewModalProps = {
  isOpen: boolean;
  onClose: () => void;
  supplyOptions: AssetOption[];
  borrowOptions: AssetOption[];
  initialSupplySymbol?: string;
};

type Phase = "approve" | "open";

const HF_1E18 = 10n ** 18n;

export function OpenPositionPreviewModal(props: OpenPositionPreviewModalProps) {
  const { isOpen, onClose, supplyOptions, borrowOptions, initialSupplySymbol } =
    props;
  const router = useRouter(); // 👈 추가

  // ---- 1) Supply: AAVE만, Borrow: LINK만 사용하도록 필터 ----
  const supplyList =
    supplyOptions.filter((s) => s.symbol === "AAVE").length > 0
      ? supplyOptions.filter((s) => s.symbol === "AAVE")
      : supplyOptions;

  const borrowList =
    borrowOptions.filter((b) => b.symbol === "LINK").length > 0
      ? borrowOptions.filter((b) => b.symbol === "LINK")
      : borrowOptions;

  const initialSupply: AssetOption = (supplyList.find(
    (a) => a.symbol === initialSupplySymbol
  ) ?? supplyList[0]) as AssetOption;

  // ---- 2) 상태값 ----
  const [supplyAsset, setSupplyAsset] = useState<AssetOption>(initialSupply);
  const [borrowAsset, setBorrowAsset] = useState<AssetOption>(borrowList[0]);

  const [supplyAmount, setSupplyAmount] = useState<string>("0"); // UI 입력 (토큰 단위)
  const [targetHF, setTargetHF] = useState<string>("1.35"); // 기본 1.35

  // preview 결과
  const [projectedHF, setProjectedHF] = useState<number | null>(null);
  const [ltvBefore, setLtvBefore] = useState<number | null>(null); // %
  const [ltvAfter, setLtvAfter] = useState<number | null>(null); // %
  const [finalBorrowToken, setFinalBorrowToken] = useState<number | null>(null); // 예: 240.74 LINK
  const [finalBorrowUsd, setFinalBorrowUsd] = useState<number | null>(null); // 예: 1234.56 $

  const [phase, setPhase] = useState<Phase>("approve");
  const [isRunningPreview, setIsRunningPreview] = useState(false);
  const [isRunningTx, setIsRunningTx] = useState(false);

  const { address } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  // ---- 3) AAVE(공급 자산) 잔고/decimals ----
  const { data: aaveDecimals } = useReadContract({
    abi: erc20Abi,
    address: supplyAsset.address,
    functionName: "decimals",
    query: { enabled: !!supplyAsset.address },
  });

  const { data: aaveBalance } = useReadContract({
    abi: erc20Abi,
    address: supplyAsset.address,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!supplyAsset.address },
  });

  // Borrow 자산(LINK) decimals (preview 결과를 토큰 단위로 바꾸는 용도)
  const { data: borrowDecimals } = useReadContract({
    abi: erc20Abi,
    address: borrowAsset.address,
    functionName: "decimals",
    query: { enabled: !!borrowAsset.address },
  });

  // initialSupplySymbol 바뀔 때마다 select 동기화
  useEffect(() => {
    if (!initialSupplySymbol) return;
    const found = supplyList.find((a) => a.symbol === initialSupplySymbol);
    if (found) setSupplyAsset(found);
  }, [initialSupplySymbol, supplyList]);

  // AAVE 잔고를 UI 기본값으로 사용 (소수 2자리)
  useEffect(() => {
    if (!aaveBalance || aaveDecimals === undefined) return;
    const raw = aaveBalance as bigint;
    const dec = Number(aaveDecimals);
    const uiAmount = dec === 0 ? Number(raw) : Number(raw) / Math.pow(10, dec);

    setSupplyAmount(uiAmount.toFixed(2));
  }, [aaveBalance, aaveDecimals]);

  const hasPreview =
    projectedHF !== null &&
    ltvBefore !== null &&
    ltvAfter !== null &&
    finalBorrowToken !== null;

  // ---- 4) previewBorrow 호출 ----
  const handleRunPreview = async () => {
    if (!supplyAmount || !publicClient || !address) return;

    setIsRunningPreview(true);

    try {
      const amountNum = Number(supplyAmount) || 0;
      if (amountNum <= 0) {
        setIsRunningPreview(false);
        return;
      }

      // supplyAmount를 on-chain 단위로 (decimals 사용, 없으면 18)
      const dec = aaveDecimals !== undefined ? Number(aaveDecimals) : 18;
      const supplyAmountBase = parseUnits(supplyAmount, dec);

      // Target HF: 0 이면 0n 으로 보내서 라우터 디폴트(1.35) 사용
      const targetHfNum = Number(targetHF);
      const targetHF1e18 =
        !targetHF || isNaN(targetHfNum) || targetHfNum <= 0
          ? 0n
          : BigInt(Math.round(targetHfNum * 1e18));

      const result = (await publicClient.readContract({
        ...strategyRouterContract,
        functionName: "previewBorrow",
        args: [
          address,
          supplyAsset.address,
          supplyAmountBase,
          borrowAsset.address,
          targetHF1e18,
        ],
      })) as readonly bigint[];

      const [
        finalToken,
        projectedHF1e18,
        byHFToken,
        policyMaxToken,
        capRemainingToken,
        liquidityToken,
        collBeforeBase,
        debtBeforeBase,
        collAfterBase,
        ltBeforeBps,
        ltAfterBps,
      ] = result;

      const projectedHfFloat = Number(projectedHF1e18) / Number(HF_1E18);
      const ltvBeforePct = Number(ltBeforeBps) / 100;
      const ltvAfterPct = Number(ltAfterBps) / 100;

      setProjectedHF(projectedHfFloat);
      setLtvBefore(ltvBeforePct);
      setLtvAfter(ltvAfterPct);

      // Final borrow: 토큰 단위
      let finalTokenUi: number;
      if (borrowDecimals !== undefined) {
        const decBorrow = Number(borrowDecimals);
        finalTokenUi =
          decBorrow === 0
            ? Number(finalToken)
            : Number(finalToken) / 10 ** decBorrow;
      } else {
        finalTokenUi = Number(finalToken) / 1e18;
      }
      setFinalBorrowToken(finalTokenUi);

      // Final borrow: USD
      try {
        const [, baseUnit] = (await publicClient.readContract({
          ...strategyLensContract,
          functionName: "getOracleBaseCurrency",
        })) as readonly [string, bigint];

        const priceRaw = (await publicClient.readContract({
          ...strategyLensContract,
          functionName: "getAssetPrice",
          args: [borrowAsset.address],
        })) as bigint;

        const priceRatio = Number(priceRaw) / Number(baseUnit);
        const usdValue = finalTokenUi * priceRatio;

        setFinalBorrowUsd(usdValue);
      } catch (priceErr) {
        console.error("Failed to fetch price for borrow asset", priceErr);
        setFinalBorrowUsd(null);
      }

      // preview가 끝나면 항상 1단계부터 시작
      setPhase("approve");
    } catch (err) {
      console.error("previewBorrow failed", err);
    } finally {
      setIsRunningPreview(false);
    }
  };

  // ---- 5) Approve / Open 버튼 ----
  const handleClickPrimary = async () => {
    if (!hasPreview) return;
    if (!address) return;

    if (phase === "approve") {
      // 1단계: ERC20 approve(router, amount)
      setIsRunningTx(true);
      try {
        const amountNum = Number(supplyAmount) || 0;
        if (amountNum <= 0) {
          throw new Error("Supply amount must be > 0");
        }

        const dec = aaveDecimals !== undefined ? Number(aaveDecimals) : 18;
        const amountBase = parseUnits(supplyAmount, dec);

        const txHash = await writeContractAsync({
          abi: erc20Abi,
          address: supplyAsset.address,
          functionName: "approve",
          args: [strategyRouterContract.address as `0x${string}`, amountBase],
        });

        console.log("approve tx hash", txHash);

        // 필요하면 여기서 waitForTransactionReceipt 가능
        // await publicClient?.waitForTransactionReceipt({ hash: txHash });

        // Approve 성공 → 2단계로 전환
        setPhase("open");
      } catch (err) {
        console.error("approve failed", err);
      } finally {
        setIsRunningTx(false);
      }
    } else {
      // 2단계: 실제 openPosition 호출
      setIsRunningTx(true);
      try {
        const amountNum = Number(supplyAmount) || 0;
        if (amountNum <= 0) {
          throw new Error("Supply amount must be > 0");
        }

        const dec = aaveDecimals !== undefined ? Number(aaveDecimals) : 18;
        const supplyAmountBase = parseUnits(supplyAmount, dec);

        const targetHfNum = Number(targetHF);
        const targetHF1e18 =
          !targetHF || isNaN(targetHfNum) || targetHfNum <= 0
            ? 0n
            : BigInt(Math.round(targetHfNum * 1e18));

        // 가스 5,000,000 고정
        const txHash = await writeContractAsync({
          abi: strategyRouterContract.abi,
          address: strategyRouterContract.address,
          functionName: "openPosition",
          args: [
            supplyAsset.address,
            supplyAmountBase,
            borrowAsset.address,
            targetHF1e18,
          ],
          gas: 5_000_000n,
        });

        console.log("openPosition tx hash", txHash);

        // 필요하면 여기서도 waitForTransactionReceipt 가능
        // await publicClient?.waitForTransactionReceipt({ hash: txHash });

        onClose();
        router.refresh();
      } catch (err) {
        console.error("openPosition failed", err);
      } finally {
        setIsRunningTx(false);
      }
    }
  };

  const primaryLabel =
    phase === "approve" ? "Approve & continue" : "Confirm open position";

  if (!isOpen) return null;
  if (supplyOptions.length === 0 || borrowOptions.length === 0) return null;

  // ---- 6) 렌더 ----
  const showPreview = hasPreview;

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70">
      <div className="w-full max-w-3xl rounded-2xl bg-slate-900/95 p-6 shadow-xl border border-slate-800">
        {/* 헤더 */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              Preview one-shot position
            </h2>
            <p className="text-xs text-slate-400">
              Supply → borrow → LP on Uniswap v4 (simulation)
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"
          >
            Esc
          </button>
        </div>

        <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
          {/* -------- 왼쪽: 입력 -------- */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
              Inputs
            </h3>

            <div className="rounded-xl bg-slate-900/80 p-4 border border-slate-800">
              {/* Supply asset + amount */}
              <label className="block text-xs font-medium text-slate-400 mb-1">
                Supply asset
              </label>
              <div className="flex gap-2">
                <select
                  className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-sm text-slate-50"
                  value={supplyAsset.symbol}
                  onChange={(e) => {
                    const next = supplyList.find(
                      (a) => a.symbol === e.target.value
                    );
                    if (next) setSupplyAsset(next);
                  }}
                >
                  {supplyList.map((opt) => (
                    <option key={opt.symbol} value={opt.symbol}>
                      {opt.symbol}
                    </option>
                  ))}
                </select>
                <input
                  className="w-24 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-right text-sm text-slate-50"
                  value={supplyAmount}
                  onChange={(e) => setSupplyAmount(e.target.value)}
                />
              </div>

              {/* Borrow asset */}
              <div className="mt-4">
                <label className="block text-xs font-medium text-slate-400 mb-1">
                  Borrow asset
                </label>
                <select
                  className="w-full rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-sm text-slate-50"
                  value={borrowAsset.symbol}
                  onChange={(e) => {
                    const next = borrowList.find(
                      (a) => a.symbol === e.target.value
                    );
                    if (next) setBorrowAsset(next);
                  }}
                >
                  {borrowList.map((opt) => (
                    <option key={opt.symbol} value={opt.symbol}>
                      {opt.symbol}
                    </option>
                  ))}
                </select>
              </div>

              {/* Target HF */}
              <div className="mt-4">
                <div className="flex items-center justify-between">
                  <label className="block text-xs font-medium text-slate-400 mb-1">
                    Target HF
                  </label>
                  <span className="text-[10px] text-slate-500">
                    Default: 1.35 (0 → use default)
                  </span>
                </div>
                <input
                  className="w-24 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-right text-sm text-slate-50"
                  value={targetHF}
                  onChange={(e) => setTargetHF(e.target.value)}
                />
              </div>

              <button
                onClick={handleRunPreview}
                disabled={isRunningPreview}
                className="mt-4 w-full rounded-lg bg-slate-100 px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-white disabled:opacity-60"
              >
                {isRunningPreview ? "Running preview…" : "Run preview"}
              </button>
            </div>
          </div>

          {/* -------- 오른쪽: Simulation 결과 -------- */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
              Simulation result (previewBorrow)
            </h3>

            <div className="rounded-xl bg-slate-900/80 p-4 border border-slate-800 space-y-3">
              <div>
                <div className="text-xs text-slate-400">Projected HF</div>
                <div className="text-lg font-semibold text-emerald-300">
                  {showPreview ? projectedHF!.toFixed(2) : "-"}
                </div>
              </div>

              <div>
                <div className="text-xs text-slate-400">LTV before → after</div>
                <div className="text-sm text-slate-100">
                  {showPreview
                    ? `${ltvBefore!.toFixed(1)}% → ${ltvAfter!.toFixed(1)}%`
                    : "-"}
                </div>
              </div>

              <div className="pt-2 border-t border-slate-800">
                <div className="text-xs text-slate-400">Final borrow</div>
                <div className="text-sm text-slate-100">
                  {showPreview
                    ? `${finalBorrowToken!.toFixed(4)} ${borrowAsset.symbol}`
                    : "-"}
                </div>
                {showPreview && finalBorrowUsd !== null && (
                  <div className="mt-1 text-xs text-slate-400">
                    ≈{" "}
                    <span className="font-medium text-slate-100">
                      ${finalBorrowUsd.toFixed(2)}
                    </span>
                  </div>
                )}
              </div>
            </div>

            <p className="text-[11px] text-slate-500">
              Simulation only – on-chain result may slightly differ at
              execution.
            </p>
          </div>
        </div>

        {/* 푸터 버튼 */}
        <div className="mt-6 flex items-center justify-end gap-3">
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-4 py-2 text-xs font-medium text-slate-200 hover:bg-slate-800"
          >
            Cancel
          </button>

          <button
            onClick={handleClickPrimary}
            disabled={!hasPreview || isRunningTx}
            className="rounded-full bg-emerald-500 px-5 py-2 text-xs font-semibold text-slate-950 hover:bg-emerald-400 disabled:opacity-60"
          >
            {isRunningTx ? "Processing…" : primaryLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
