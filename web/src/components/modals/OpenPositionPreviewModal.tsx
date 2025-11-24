"use client";

import { useEffect, useState } from "react";

export type AssetOption = {
  symbol: string;
  address: `0x${string}`;
};

type OpenPositionPreviewModalProps = {
  isOpen: boolean;
  onClose: () => void;

  // 셀렉트 박스에 들어갈 옵션들
  supplyOptions: AssetOption[];
  borrowOptions: AssetOption[];

  // 카드에서 넘겨주는 초기 선택값 (예: "AAVE")
  initialSupplySymbol?: string;
};

type Phase = "approve" | "open";

export function OpenPositionPreviewModal(props: OpenPositionPreviewModalProps) {
  const { isOpen, onClose, supplyOptions, borrowOptions, initialSupplySymbol } =
    props;

  if (!isOpen) return null;
  if (supplyOptions.length === 0 || borrowOptions.length === 0) {
    // 옵션 없으면 그냥 빈 모달로
    return null;
  }

  // -------- 기본 선택 값 --------
  const initialSupply: AssetOption = (supplyOptions.find(
    (a) => a.symbol === initialSupplySymbol
  ) ?? supplyOptions[0]) as AssetOption;

  // -------- state --------
  const [supplyAsset, setSupplyAsset] = useState<AssetOption>(initialSupply);
  const [borrowAsset, setBorrowAsset] = useState<AssetOption>(borrowOptions[0]);
  const [supplyAmount, setSupplyAmount] = useState<string>("100");
  const [targetHF, setTargetHF] = useState<string>("1.40");

  const [projectedHF, setProjectedHF] = useState<number | null>(null);
  const [ltvAfter, setLtvAfter] = useState<number | null>(null);
  const [finalBorrowUsd, setFinalBorrowUsd] = useState<number | null>(null);
  const [borrowUsedAfter, setBorrowUsedAfter] = useState<number | null>(null);

  const [phase, setPhase] = useState<Phase>("approve");
  const [isRunningPreview, setIsRunningPreview] = useState(false);
  const [isRunningTx, setIsRunningTx] = useState(false);

  // initialSupplySymbol 바뀔 때마다 select 동기화
  useEffect(() => {
    if (!initialSupplySymbol) return;
    const found = supplyOptions.find((a) => a.symbol === initialSupplySymbol);
    if (found) {
      setSupplyAsset(found);
    }
  }, [initialSupplySymbol, supplyOptions]);

  const hasPreview =
    projectedHF !== null &&
    ltvAfter !== null &&
    finalBorrowUsd !== null &&
    borrowUsedAfter !== null;

  // -------- previewBorrow 더미 호출 --------
  const handleRunPreview = async () => {
    if (!supplyAmount || !targetHF) return;

    setIsRunningPreview(true);

    try {
      // TODO: 여기서 실제 previewBorrow RPC/컨트랙트 호출 붙이면 됨
      const amount = Number(supplyAmount) || 0;
      const hf = Number(targetHF) || 0;

      // 그냥 데모 계산
      const demoProjectedHf = hf - 0.02;
      const demoLtvAfter = 0.37;
      const demoFinalBorrow = amount * 11.2; // 대충 1120 느낌
      const demoBorrowUsed = 0.52;

      setProjectedHF(demoProjectedHf);
      setLtvAfter(demoLtvAfter);
      setFinalBorrowUsd(demoFinalBorrow);
      setBorrowUsedAfter(demoBorrowUsed);
      setPhase("approve");
    } finally {
      setIsRunningPreview(false);
    }
  };

  // -------- primary 버튼: Approve -> Open 단계 --------
  const handleClickPrimary = async () => {
    if (!hasPreview) return;

    if (phase === "approve") {
      setIsRunningTx(true);
      try {
        // TODO: 실제 approve 호출 자리
        console.log(
          "[TODO] approve",
          supplyAsset.symbol,
          "for router, amount:",
          supplyAmount
        );
        // approve 끝났다고 가정
        setPhase("open");
      } finally {
        setIsRunningTx(false);
      }
    } else {
      setIsRunningTx(true);
      try {
        // TODO: 실제 openPosition 호출 자리
        console.log(
          "[TODO] openPosition with",
          supplyAsset.symbol,
          supplyAmount,
          "borrow:",
          borrowAsset.symbol,
          "targetHF:",
          targetHF
        );
        onClose();
      } finally {
        setIsRunningTx(false);
      }
    }
  };

  const primaryLabel =
    phase === "approve" ? "Approve & continue" : "Confirm open position";

  // -------- 렌더 --------
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

            {/* Supply asset + amount */}
            <div className="rounded-xl bg-slate-900/80 p-4 border border-slate-800">
              <label className="block text-xs font-medium text-slate-400 mb-1">
                Supply asset
              </label>
              <div className="flex gap-2">
                <select
                  className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-sm text-slate-50"
                  value={supplyAsset.symbol}
                  onChange={(e) => {
                    const next = supplyOptions.find(
                      (a) => a.symbol === e.target.value
                    );
                    if (next) setSupplyAsset(next);
                  }}
                >
                  {supplyOptions.map((opt) => (
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

              <div className="mt-4">
                <label className="block text-xs font-medium text-slate-400 mb-1">
                  Borrow asset
                </label>
                <select
                  className="w-full rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-sm text-slate-50"
                  value={borrowAsset.symbol}
                  onChange={(e) => {
                    const next = borrowOptions.find(
                      (a) => a.symbol === e.target.value
                    );
                    if (next) setBorrowAsset(next);
                  }}
                >
                  {borrowOptions.map((opt) => (
                    <option key={opt.symbol} value={opt.symbol}>
                      {opt.symbol}
                    </option>
                  ))}
                </select>
              </div>

              <div className="mt-4">
                <label className="block text-xs font-medium text-slate-400 mb-1">
                  Target HF
                </label>
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

          {/* -------- 오른쪽: simulation 결과 -------- */}
          <div className="space-y-4">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
              Simulation result (previewBorrow)
            </h3>

            <div className="rounded-xl bg-slate-900/80 p-4 border border-slate-800 space-y-3">
              <div>
                <div className="text-xs text-slate-400">Projected HF</div>
                <div className="text-lg font-semibold text-emerald-300">
                  {hasPreview ? projectedHF?.toFixed(2) : "-"}
                </div>
              </div>

              <div>
                <div className="text-xs text-slate-400">LTV after</div>
                <div className="text-sm text-slate-100">
                  {hasPreview ? `${(ltvAfter! * 100).toFixed(1)}%` : "-"}
                </div>
              </div>

              <div className="pt-2 border-t border-slate-800">
                <div className="text-xs text-slate-400">Final borrow (USD)</div>
                <div className="text-sm text-slate-100">
                  {hasPreview ? `$${finalBorrowUsd!.toFixed(2)}` : "-"}
                </div>
                <div className="mt-1 text-xs text-slate-400">
                  Borrow used{" "}
                  <span className="font-medium text-slate-100">
                    {hasPreview
                      ? `${(borrowUsedAfter! * 100).toFixed(1)}%`
                      : "-"}
                  </span>
                </div>
              </div>
            </div>

            <p className="text-[11px] text-slate-500">
              Simulation only – on-chain result may slightly differ at
              execution.
            </p>
          </div>
        </div>

        {/* -------- footer 버튼 -------- */}
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
