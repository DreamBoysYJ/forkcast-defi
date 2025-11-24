"use client";

import { useEffect, useState } from "react";

export type ClosePreviewData = {
  tokenId: number;
  // 전략 구성
  supplySymbol: string;
  borrowSymbol: string;
  supplyIconUrl: string;
  borrowIconUrl: string;
  vaultAddress: string;

  // LP에서 빠져나오는 토큰들
  token0Symbol: string;
  token1Symbol: string;
  amount0FromLp: number;
  amount1FromLp: number;

  // 빚 / LP에서 나오는 borrow 토큰 / 추가 필요량
  totalDebtToken: number; // 전체 빚 (borrowAsset 수량 기준)
  totalDebtUsd: number;
  lpBorrowTokenAmount: number; // LP에서 나오는 borrowAsset 수량
  lpBorrowUsd: number;
  minExtraFromUser: number; // 권장 최소 추가량
  maxExtraFromUser: number; // 이론상 최대 추가량
};

type ClosePositionPreviewModalProps = {
  isOpen: boolean;
  onClose: () => void;

  // 어떤 포지션을 닫을지
  tokenId: number;
};

// ----------------------
// 데모용 mock 로더
// (나중에 여기만 previewClosePosition + price oracle + balance/allowance 호출로 교체하면 됨)
// ----------------------
async function mockLoadClosePreview(tokenId: number): Promise<{
  preview: ClosePreviewData;
  walletBorrowBalance: number;
  allowanceForRouter: number;
}> {
  // 그냥 데모 값들
  const preview: ClosePreviewData = {
    tokenId,
    supplySymbol: "AAVE",
    borrowSymbol: "WBTC",
    supplyIconUrl: "/tokens/aave.png",
    borrowIconUrl: "/tokens/wbtc.png",
    vaultAddress: "0xabcdef1234567890abcdef1234567890abcdef12",

    token0Symbol: "AAVE",
    token1Symbol: "WBTC",
    amount0FromLp: 100,
    amount1FromLp: 0.3,

    totalDebtToken: 0.08,
    totalDebtUsd: 1120,
    lpBorrowTokenAmount: 0.03,
    lpBorrowUsd: 420,
    minExtraFromUser: 0.05,
    maxExtraFromUser: 0.08,
  };

  // 유저 지갑에 있는 borrowAsset, allowance 값 (데모)
  const walletBorrowBalance = 0.12;
  const allowanceForRouter = 0.0;

  return { preview, walletBorrowBalance, allowanceForRouter };
}

// 주소 줄여서 보여주기
function shortenAddress(addr: string) {
  if (!addr) return "-";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

type Phase = "approve" | "close";

export function ClosePositionPreviewModal(
  props: ClosePositionPreviewModalProps
) {
  const { isOpen, onClose, tokenId } = props;

  const [preview, setPreview] = useState<ClosePreviewData | null>(null);
  const [walletBorrowBalance, setWalletBorrowBalance] = useState<number>(0);
  const [hasAllowance, setHasAllowance] = useState<boolean>(false);

  const [extraAmountInput, setExtraAmountInput] = useState<string>("");
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);
  const [isRunningTx, setIsRunningTx] = useState(false);
  const [phase, setPhase] = useState<Phase>("approve");

  // 모달 열릴 때마다 previewClosePosition + balance/allowance 로딩
  useEffect(() => {
    if (!isOpen) return;

    setIsLoadingPreview(true);
    setPreview(null);

    mockLoadClosePreview(tokenId)
      .then(({ preview, walletBorrowBalance, allowanceForRouter }) => {
        setPreview(preview);
        setWalletBorrowBalance(walletBorrowBalance);

        // 기본 extraAmount는 minExtraFromUser
        setExtraAmountInput(preview.minExtraFromUser.toString());

        // allowance 체크 (데모)
        const extra = preview.minExtraFromUser;
        setHasAllowance(allowanceForRouter >= extra);

        // 빚이 없거나 추가 필요량이 0이면 바로 close 단계로
        if (preview.minExtraFromUser <= 0) {
          setPhase("close");
        } else {
          setPhase("approve");
        }
      })
      .finally(() => {
        setIsLoadingPreview(false);
      });
  }, [isOpen, tokenId]);

  if (!isOpen) return null;

  const extraAmount = Number(extraAmountInput) || 0;

  const hasPreview = !!preview && !isLoadingPreview;
  const debtCoveredRatio =
    hasPreview && preview!.totalDebtToken > 0
      ? preview!.lpBorrowTokenAmount / preview!.totalDebtToken
      : 0;

  const insufficientBalance = hasPreview && extraAmount > walletBorrowBalance;

  // primary 버튼 라벨
  let primaryLabel = "Loading…";
  if (hasPreview) {
    if (!hasAllowance && extraAmount > 0) {
      primaryLabel = `Approve ${preview!.borrowSymbol}`;
    } else {
      primaryLabel = "Confirm close position";
    }
  }

  const isPrimaryDisabled =
    !hasPreview ||
    isLoadingPreview ||
    isRunningTx ||
    insufficientBalance ||
    extraAmount < 0;

  // Approve -> Close 플로우
  const handleClickPrimary = async () => {
    if (!preview) return;

    if (!hasAllowance && extraAmount > 0) {
      // 1) Approve 단계
      setIsRunningTx(true);
      try {
        // TODO: 여기서 실제 ERC20 approve(router, extraAmount) 호출
        console.log(
          "[TODO] approve",
          preview.borrowSymbol,
          "for router, amount:",
          extraAmount
        );
        setHasAllowance(true);
        setPhase("close");
      } finally {
        setIsRunningTx(false);
      }
    } else {
      // 2) closePosition 호출
      setIsRunningTx(true);
      try {
        // TODO: 여기서 실제 closePosition(tokenId, extraAmount) 트랜잭션 호출
        console.log(
          "[TODO] closePosition tokenId:",
          preview.tokenId,
          "with extra",
          extraAmount,
          preview.borrowSymbol
        );
        onClose();
      } finally {
        setIsRunningTx(false);
      }
    }
  };

  const handleUseMin = () => {
    if (!preview) return;
    setExtraAmountInput(preview.minExtraFromUser.toString());
  };

  const handleUseMax = () => {
    if (!preview) return;
    setExtraAmountInput(preview.maxExtraFromUser.toString());
  };

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70">
      <div className="w-full max-w-4xl rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-xl">
        {/* 헤더 */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              Preview close position
            </h2>
            <p className="text-xs text-slate-400">
              Remove LP → repay Aave debt → withdraw leftover tokens
              (simulation)
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"
          >
            Esc
          </button>
        </div>

        {/* 로딩 상태 */}
        {!hasPreview && (
          <div className="py-16 text-center text-sm text-slate-400">
            Loading preview…
          </div>
        )}

        {hasPreview && preview && (
          <>
            <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
              {/* 왼쪽: 전략/빚 요약 */}
              <div className="space-y-4">
                {/* Strategy composition */}
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                    Strategy composition
                  </h3>

                  <div className="mt-3 space-y-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4">
                    {/* Supply */}
                    <div className="flex items-center gap-3">
                      <img
                        src={preview.supplyIconUrl}
                        alt={preview.supplySymbol}
                        className="h-8 w-8 rounded-full border border-slate-800 bg-slate-950 object-cover"
                      />
                      <div className="flex flex-col">
                        <span className="text-xs font-medium text-slate-400">
                          Supply (collateral)
                        </span>
                        <span className="text-sm font-semibold text-slate-50">
                          {preview.supplySymbol}
                        </span>
                      </div>
                    </div>

                    {/* Borrow */}
                    <div className="flex items-center gap-3">
                      <img
                        src={preview.borrowIconUrl}
                        alt={preview.borrowSymbol}
                        className="h-8 w-8 rounded-full border border-slate-800 bg-slate-950 object-cover"
                      />
                      <div className="flex flex-col">
                        <span className="text-xs font-medium text-slate-400">
                          Borrow asset
                        </span>
                        <span className="text-sm font-semibold text-slate-50">
                          {preview.borrowSymbol}
                        </span>
                      </div>
                    </div>

                    {/* 메타 정보 */}
                    <div className="pt-3 text-[11px] text-slate-500">
                      <div>Token ID: #{preview.tokenId}</div>
                      <div>Vault: {shortenAddress(preview.vaultAddress)}</div>
                    </div>
                  </div>
                </div>

                {/* Debt vs LP coverage */}
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                    Debt vs LP coverage
                  </h3>

                  <div className="mt-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4 space-y-3">
                    <div>
                      <div className="text-xs text-slate-400">
                        Current debt ({preview.borrowSymbol})
                      </div>
                      <div className="text-sm font-semibold text-slate-50">
                        {preview.totalDebtToken.toFixed(4)}{" "}
                        {preview.borrowSymbol}
                      </div>
                      <div className="text-[11px] text-slate-500">
                        ${preview.totalDebtUsd.toFixed(2)}
                      </div>
                    </div>

                    <div className="pt-2 border-t border-slate-800">
                      <div className="text-xs text-slate-400">
                        From LP (borrow asset portion)
                      </div>
                      <div className="text-sm font-semibold text-slate-50">
                        {preview.lpBorrowTokenAmount.toFixed(4)}{" "}
                        {preview.borrowSymbol}
                      </div>
                      <div className="text-[11px] text-slate-500">
                        ${preview.lpBorrowUsd.toFixed(2)} • LP covers{" "}
                        <span className="font-medium text-slate-100">
                          {(debtCoveredRatio * 100).toFixed(1)}%
                        </span>{" "}
                        of your debt
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* 오른쪽: 추가 필요량 + LP 토큰 */}
              <div className="space-y-4">
                {/* Extra needed */}
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                    Extra {preview.borrowSymbol} needed to fully repay
                  </h3>

                  <div className="mt-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4 space-y-3">
                    <div className="flex items-baseline justify-between">
                      <div>
                        <div className="text-xs text-slate-400">
                          Recommended minimum
                        </div>
                        <div className="text-sm font-semibold text-slate-50">
                          {preview.minExtraFromUser.toFixed(4)}{" "}
                          {preview.borrowSymbol}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-slate-400">
                          Theoretical maximum
                        </div>
                        <div className="text-sm font-semibold text-slate-50">
                          {preview.maxExtraFromUser.toFixed(4)}{" "}
                          {preview.borrowSymbol}
                        </div>
                      </div>
                    </div>

                    {/* 입력 / 버튼 */}
                    <div className="pt-2 border-t border-slate-800">
                      <label className="mb-1 block text-xs font-medium text-slate-400">
                        Amount you will prepare ({preview.borrowSymbol})
                      </label>
                      <div className="flex gap-2">
                        <input
                          className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-right text-sm text-slate-50"
                          value={extraAmountInput}
                          onChange={(e) => setExtraAmountInput(e.target.value)}
                        />
                        <button
                          type="button"
                          onClick={handleUseMin}
                          className="rounded-lg border border-slate-700 px-2 py-1 text-[11px] text-slate-100 hover:bg-slate-800"
                        >
                          Use min
                        </button>
                        <button
                          type="button"
                          onClick={handleUseMax}
                          className="rounded-lg border border-slate-700 px-2 py-1 text-[11px] text-slate-100 hover:bg-slate-800"
                        >
                          Use max
                        </button>
                      </div>

                      <div className="mt-2 text-[11px] text-slate-500">
                        Your wallet:{" "}
                        <span className="font-medium text-slate-100">
                          {walletBorrowBalance.toFixed(4)}{" "}
                          {preview.borrowSymbol}
                        </span>
                      </div>

                      {insufficientBalance && (
                        <div className="mt-1 text-[11px] font-medium text-rose-400">
                          Not enough {preview.borrowSymbol} to safely close this
                          position.
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* LP에서 나오는 토큰 정보 */}
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                    LP tokens you will withdraw
                  </h3>

                  <div className="mt-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4 space-y-2 text-sm text-slate-100">
                    <div>
                      {preview.token0Symbol}: {preview.amount0FromLp.toFixed(4)}
                    </div>
                    <div>
                      {preview.token1Symbol}: {preview.amount1FromLp.toFixed(4)}
                    </div>
                    <div className="pt-1 text-[11px] text-slate-500">
                      Borrow asset portion from LP is used to repay your Aave
                      debt. Remaining tokens will be sent back to your wallet.
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* 안내 문구 */}
            <p className="mt-4 text-[11px] text-slate-500">
              If you provide less than the recommended minimum, the transaction
              may revert due to insufficient funds to repay the debt. Simulation
              only – on-chain result may slightly differ at execution.
            </p>

            {/* footer 버튼 */}
            <div className="mt-6 flex items-center justify-end gap-3">
              <button
                onClick={onClose}
                className="rounded-full border border-slate-700 px-4 py-2 text-xs font-medium text-slate-200 hover:bg-slate-800"
              >
                Cancel
              </button>
              <button
                onClick={handleClickPrimary}
                disabled={isPrimaryDisabled}
                className="rounded-full bg-emerald-500 px-5 py-2 text-xs font-semibold text-slate-950 hover:bg-emerald-400 disabled:opacity-60"
              >
                {isRunningTx ? "Processing…" : primaryLabel}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
