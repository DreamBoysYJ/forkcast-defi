// src/components/modals/ClosePositionPreviewModal.tsx
"use client";

import { useEffect, useState } from "react";
import { useAccount, useConfig, useWriteContract } from "wagmi";
import { readContract } from "@wagmi/core";
import { parseUnits } from "viem";
import { strategyRouterContract } from "@/lib/contracts";
import { useRouter } from "next/navigation";

// 데모용: 우리가 쓰는 토큰 메타 (AAVE / LINK)
const TOKEN_META: Record<
  string,
  { symbol: string; icon: string; decimals: number }
> = {
  // AAVE
  "0x88541670e55cc00beefd87eb59edd1b7c511ac9a": {
    symbol: "AAVE",
    icon: "/tokens/aave.png",
    decimals: 18,
  },
  // LINK
  "0xf8fb3713d459d7c1018bd0a49d19b4c44290ebe5": {
    symbol: "LINK",
    icon: "/tokens/link.png",
    decimals: 18,
  },
};

// 최소 ERC20 ABI (approve / balanceOf / allowance)
const erc20Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "owner", type: "address" }],
    outputs: [{ name: "balance", type: "uint256" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "amount", type: "uint256" }],
  },
] as const;

export type ClosePreviewData = {
  tokenId: number;
  // 전략 구성
  supplySymbol: string;
  borrowSymbol: string;
  supplyIconUrl: string;
  borrowIconUrl: string;
  vaultAddress: string;
  borrowTokenAddress: `0x${string}`;
  borrowDecimals: number;

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
  tokenId: number;
  totalDebtUsdFromCard: number; // ★ 추가
};

// 주소 줄여서 보여주기
function shortenAddress(addr: string) {
  if (!addr) return "-";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

type Phase = "approve" | "close";
type Mode = "simulate" | "done";

// bigint → 토큰 수량(number)
function toTokenAmount(raw: bigint, decimals: number): number {
  if (raw === 0n) return 0;
  return Number(raw) / 10 ** decimals;
}

export function ClosePositionPreviewModal(
  props: ClosePositionPreviewModalProps
) {
  const { isOpen, onClose, tokenId, totalDebtUsdFromCard } = props;
  const router = useRouter();

  const { address: wallet } = useAccount();
  const wagmiConfig = useConfig();
  const { writeContractAsync } = useWriteContract();

  const [preview, setPreview] = useState<ClosePreviewData | null>(null);
  const [walletBorrowBalance, setWalletBorrowBalance] = useState<number>(0);
  const [hasAllowance, setHasAllowance] = useState<boolean>(false);

  const [extraAmountInput, setExtraAmountInput] = useState<string>("");
  const [isLoadingPreview, setIsLoadingPreview] = useState(false);
  const [isRunningTx, setIsRunningTx] = useState(false);
  const [phase, setPhase] = useState<Phase>("approve");
  const [mode, setMode] = useState<Mode>("simulate");
  const [loadError, setLoadError] = useState<string | null>(null);

  // 모달 열릴 때마다 실제 previewClosePosition + balance/allowance 읽어오기
  useEffect(() => {
    if (!isOpen) return;

    const load = async () => {
      setIsLoadingPreview(true);
      setLoadError(null);
      setPreview(null);
      setHasAllowance(false);
      setPhase("approve");
      setMode("simulate");

      try {
        const idBig = BigInt(tokenId);

        // 1) StrategyRouter.previewClosePosition(tokenId)
        const result = (await readContract(wagmiConfig, {
          ...strategyRouterContract,
          functionName: "previewClosePosition",
          args: [idBig],
        })) as readonly [
          `0x${string}`, // vault
          `0x${string}`, // supplyAsset
          `0x${string}`, // borrowAsset
          bigint, // totalDebtToken
          bigint, // lpBorrowTokenAmount
          bigint, // minExtraFromUser
          bigint, // maxExtraFromUser
          bigint, // amount0FromLp
          bigint // amount1FromLp
        ];

        const [
          vault,
          supplyAsset,
          borrowAsset,
          totalDebtTokenRaw,
          lpBorrowTokenAmountRaw,
          minExtraRaw,
          maxExtraRaw,
          amount0FromLpRaw,
          amount1FromLpRaw,
        ] = result;

        const supplyMeta =
          TOKEN_META[supplyAsset.toLowerCase()] ??
          ({
            symbol: "SUPPLY",
            icon: "/tokens/default.png",
            decimals: 18,
          } as const);
        const borrowMeta =
          TOKEN_META[borrowAsset.toLowerCase()] ??
          ({
            symbol: "BORROW",
            icon: "/tokens/default.png",
            decimals: 18,
          } as const);

        const totalDebtToken = toTokenAmount(
          totalDebtTokenRaw,
          borrowMeta.decimals
        );
        const lpBorrowTokenAmount = toTokenAmount(
          lpBorrowTokenAmountRaw,
          borrowMeta.decimals
        );
        const minExtraFromUser = toTokenAmount(
          minExtraRaw,
          borrowMeta.decimals
        );
        const maxExtraFromUser = toTokenAmount(
          maxExtraRaw,
          borrowMeta.decimals
        );

        const amount0FromLp = toTokenAmount(
          amount0FromLpRaw,
          supplyMeta.decimals
        );
        const amount1FromLp = toTokenAmount(
          amount1FromLpRaw,
          borrowMeta.decimals
        );

        // USD 는 일단 0으로 두고, 나중에 Aave price oracle 붙이면 됨.
        // ❶ borrow 토큰 1개당 USD 가격 추정
        const borrowPriceUsd =
          totalDebtToken > 0 ? totalDebtUsdFromCard / totalDebtToken : 0;

        // ❷ 그 가격으로 다시 USD 값 계산
        const totalDebtUsd = totalDebtToken * borrowPriceUsd;
        const lpBorrowUsd = lpBorrowTokenAmount * borrowPriceUsd;

        const previewData: ClosePreviewData = {
          tokenId,
          supplySymbol: supplyMeta.symbol,
          borrowSymbol: borrowMeta.symbol,
          supplyIconUrl: supplyMeta.icon,
          borrowIconUrl: borrowMeta.icon,
          vaultAddress: vault,
          borrowTokenAddress: borrowAsset,
          borrowDecimals: borrowMeta.decimals,
          token0Symbol: supplyMeta.symbol,
          token1Symbol: borrowMeta.symbol,
          amount0FromLp,
          amount1FromLp,
          totalDebtToken,
          totalDebtUsd,
          lpBorrowTokenAmount,
          lpBorrowUsd,
          minExtraFromUser,
          maxExtraFromUser,
        };

        setPreview(previewData);

        // extraAmount 기본값 = maxExtra (우리는 이 값을 approve)
        setExtraAmountInput(maxExtraFromUser.toString());

        // 2) wallet balance / allowance (있을 때만)
        if (wallet) {
          const [balanceRaw, allowanceRaw] = await Promise.all([
            readContract(wagmiConfig, {
              address: borrowAsset,
              abi: erc20Abi,
              functionName: "balanceOf",
              args: [wallet],
            }) as Promise<bigint>,
            readContract(wagmiConfig, {
              address: borrowAsset,
              abi: erc20Abi,
              functionName: "allowance",
              args: [wallet, strategyRouterContract.address],
            }) as Promise<bigint>,
          ]);

          const balance = toTokenAmount(balanceRaw, borrowMeta.decimals);
          const allowance = toTokenAmount(allowanceRaw, borrowMeta.decimals);

          setWalletBorrowBalance(balance);
          setHasAllowance(allowance >= maxExtraFromUser);

          if (maxExtraFromUser <= 0 || allowance >= maxExtraFromUser) {
            setPhase("close");
          } else {
            setPhase("approve");
          }
        } else {
          // 지갑 안 연결된 상태면 balance/allowance 는 0 처리
          setWalletBorrowBalance(0);
          setHasAllowance(false);
          setPhase("approve");
        }
      } catch (e: any) {
        console.error("[ClosePreview] load failed", e);
        setLoadError("Failed to load close preview. Check console / RPC.");
      } finally {
        setIsLoadingPreview(false);
      }
    };

    load();
  }, [isOpen, tokenId, wagmiConfig, wallet, totalDebtUsdFromCard]);

  if (!isOpen) return null;

  const extraAmount = Number(extraAmountInput) || 0;

  const hasPreview = !!preview && !isLoadingPreview && !loadError;
  const debtCoveredRatio =
    hasPreview && preview!.totalDebtToken > 0
      ? preview!.lpBorrowTokenAmount / preview!.totalDebtToken
      : 0;

  const insufficientBalance = hasPreview && extraAmount > walletBorrowBalance;

  // primary 버튼 라벨
  let primaryLabel = "Loading…";
  if (hasPreview && preview) {
    if (mode === "done") {
      primaryLabel = "Done";
    } else if (phase === "approve" && extraAmount > 0) {
      primaryLabel = `Approve ${preview.borrowSymbol}`;
    } else {
      primaryLabel = "Confirm close position";
    }
  }

  let isPrimaryDisabled =
    !hasPreview ||
    isLoadingPreview ||
    isRunningTx ||
    insufficientBalance ||
    extraAmount < 0;

  if (mode === "done") {
    // 완료 모드에서는 닫기만 할 수 있게
    isPrimaryDisabled = isRunningTx;
  }

  // Approve -> closePosition 플로우
  const handleClickPrimary = async () => {
    if (!preview) return;

    // 완료 모드에서는 그냥 모달 닫기
    if (mode === "done") {
      onClose();
      return;
    }

    if (phase === "approve" && extraAmount > 0) {
      // 1) Approve 단계: maxExtraFromUser 만큼 approve
      setIsRunningTx(true);
      try {
        const approveTokenAmount = preview.maxExtraFromUser;
        const approveWei = parseUnits(
          approveTokenAmount.toString(),
          preview.borrowDecimals
        );

        console.log(
          "[ClosePreview] approve",
          preview.borrowSymbol,
          "spender=router:",
          strategyRouterContract.address,
          "amount:",
          approveTokenAmount
        );

        const hash = await writeContractAsync({
          address: preview.borrowTokenAddress,
          abi: erc20Abi,
          functionName: "approve",
          args: [strategyRouterContract.address, approveWei],
        });

        console.log("[ClosePreview] approve tx hash:", hash);
        setHasAllowance(true);
        setPhase("close");
      } catch (e) {
        console.error("[ClosePreview] approve failed", e);
      } finally {
        setIsRunningTx(false);
      }
    } else {
      // 2) closePosition 호출
      setIsRunningTx(true);
      try {
        const hash = await writeContractAsync({
          ...strategyRouterContract,
          functionName: "closePosition",
          args: [BigInt(preview.tokenId)],
          gas: 5_000_000n,
        });

        console.log("[ClosePreview] closePosition tx hash:", hash);
        onClose();
        router.refresh();

        // 실제 값은 이벤트/리시트에서 나중에 뽑고,
        // 지금은 preview 데이터를 기반으로 "Estimated result" 표시
        setMode("done");
      } catch (e) {
        console.error("[ClosePreview] closePosition failed", e);
      } finally {
        setIsRunningTx(false);
      }
    }
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
            disabled={isRunningTx}
          >
            Esc
          </button>
        </div>

        {/* 로딩 / 에러 */}
        {!hasPreview && (
          <div className="py-16 text-center text-sm text-slate-400">
            {isLoadingPreview
              ? "Loading preview…"
              : loadError ?? "No data available."}
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

                  <div className="mt-3 space-y-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4">
                    <div>
                      <div className="text-xs text-slate-400">
                        Current debt ({preview.borrowSymbol})
                      </div>
                      <div className="text-sm font-semibold text-slate-50">
                        {preview.totalDebtToken.toFixed(6)}{" "}
                        {preview.borrowSymbol}
                      </div>
                      <div className="text-[11px] text-slate-500">
                        ${preview.totalDebtUsd.toFixed(2)}
                      </div>
                    </div>

                    <div className="border-t border-slate-800 pt-2">
                      <div className="text-xs text-slate-400">
                        From LP (borrow asset portion)
                      </div>
                      <div className="text-sm font-semibold text-slate-50">
                        {preview.lpBorrowTokenAmount.toFixed(6)}{" "}
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

                  <div className="mt-3 space-y-3 rounded-xl border border-slate-800 bg-slate-900/80 p-4">
                    <div className="flex items-baseline justify-between">
                      <div>
                        <div className="text-xs text-slate-400">
                          Recommended minimum
                        </div>
                        <div className="text-sm font-semibold text-slate-50">
                          {preview.minExtraFromUser.toFixed(6)}{" "}
                          {preview.borrowSymbol}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs text-slate-400">
                          Theoretical maximum
                        </div>
                        <div className="text-sm font-semibold text-slate-50">
                          {preview.maxExtraFromUser.toFixed(6)}{" "}
                          {preview.borrowSymbol}
                        </div>
                      </div>
                    </div>

                    {/* 입력 / 버튼 */}
                    <div className="border-t border-slate-800 pt-2">
                      <label className="mb-1 block text-xs font-medium text-slate-400">
                        Amount you will approve ({preview.borrowSymbol})
                      </label>
                      <div className="flex gap-2">
                        <input
                          className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-2 py-1 text-right text-sm text-slate-50"
                          value={extraAmountInput}
                          onChange={(e) => setExtraAmountInput(e.target.value)}
                          disabled={mode === "done"}
                        />

                        <button
                          type="button"
                          onClick={handleUseMax}
                          className="rounded-lg border border-slate-700 px-2 py-1 text-[11px] text-slate-100 hover:bg-slate-800 disabled:opacity-40"
                          disabled={mode === "done"}
                        >
                          Use max
                        </button>
                      </div>

                      <div className="mt-2 text-[11px] text-slate-500">
                        Your wallet:{" "}
                        <span className="font-medium text-slate-100">
                          {walletBorrowBalance.toFixed(6)}{" "}
                          {preview.borrowSymbol}
                        </span>
                      </div>

                      {insufficientBalance && mode !== "done" && (
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

                  <div className="mt-3 space-y-2 rounded-xl border border-slate-800 bg-slate-900/80 p-4 text-sm text-slate-100">
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

            {/* Estimated result (closePosition 이후) */}
            {mode === "done" && (
              <div className="mt-4 rounded-xl border border-emerald-500/40 bg-emerald-500/10 p-3 text-[11px] text-emerald-100">
                <div className="text-xs font-semibold mb-1">
                  Estimated result (from simulation)
                </div>
                <div>
                  • Your Aave debt of{" "}
                  <span className="font-semibold">
                    {preview.totalDebtToken.toFixed(6)} {preview.borrowSymbol}
                  </span>{" "}
                  is expected to be fully repaid.
                </div>
                <div>
                  • You will withdraw roughly{" "}
                  <span className="font-semibold">
                    {preview.amount0FromLp.toFixed(4)} {preview.token0Symbol}
                  </span>{" "}
                  and{" "}
                  <span className="font-semibold">
                    {preview.amount1FromLp.toFixed(4)} {preview.token1Symbol}
                  </span>{" "}
                  from the LP position.
                </div>
                <div className="mt-1 text-[10px] opacity-80">
                  Values are based on the preview simulation; actual on-chain
                  amounts may slightly differ.
                </div>
              </div>
            )}

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
                disabled={isRunningTx}
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
