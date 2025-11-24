// components/dashboard/strategy/StrategyPositionCard.tsx
"use client";

import { useState } from "react";
import {
  StrategyPositionRow,
  type StrategyPositionRowData,
} from "./StrategyPositionRow";

import { ClosePositionPreviewModal } from "@/components/modals/ClosePositionPreviewModal";

type Props = {
  data: StrategyPositionRowData;
  onClickPreviewClose?: (tokenId: number) => void;
};

export function StrategyPositionCard({ data }: Props) {
  // 1) 포지션 여부 / 상태
  const hasPosition = !!data && data.tokenId !== 0;
  const isOpen = data?.isOpen ?? false;

  // 2) Close preview 모달 상태
  const [isCloseModalOpen, setIsCloseModalOpen] = useState(false);
  const [selectedTokenId, setSelectedTokenId] = useState<number | null>(null);

  // StrategyPositionRow에서 "Preview close" 버튼 눌렀을 때 호출
  const handlePreviewCloseClick = (tokenId: number) => {
    setSelectedTokenId(tokenId);
    setIsCloseModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsCloseModalOpen(false);
  };

  return (
    <>
      {/* 메인 카드 */}
      <div className="rounded-2xl border border-slate-800/60 bg-slate-950/70 shadow-sm">
        {/* 헤더 */}
        <div className="flex items-center justify-between border-b border-slate-800/60 px-6 py-4">
          <div className="flex flex-col">
            <h2 className="text-xl font-semibold text-slate-50">
              Strategy overview (demo)
            </h2>
            <p className="text-sm text-slate-400">
              Supply → Borrow → LP on Uniswap v4
            </p>
          </div>

          <div className="flex items-center gap-3">
            {hasPosition && (
              <span
                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium ${
                  isOpen
                    ? "bg-emerald-500/10 text-emerald-300"
                    : "bg-slate-700/40 text-slate-300"
                }`}
              >
                <span
                  className={`h-1.5 w-1.5 rounded-full ${
                    isOpen ? "bg-emerald-400" : "bg-slate-400"
                  }`}
                />
                {isOpen ? "Open" : "Closed"}
              </span>
            )}

            <span className="text-[11px] text-slate-500">
              Strategy data – combined from Aave &amp; Uniswap v4
            </span>
          </div>
        </div>

        {/* 본문 */}
        <div className="px-6 py-5">
          {data ? (
            <StrategyPositionRow
              data={data}
              // ✅ Row의 "Preview close" 버튼이 이 핸들러를 부름
              onClickPreviewClose={handlePreviewCloseClick}
            />
          ) : (
            <div className="py-8 text-center text-sm text-slate-500">
              No strategy position found yet. Open a one-shot position first.
            </div>
          )}
        </div>
      </div>

      {/* Close preview 모달 */}
      {selectedTokenId !== null && (
        <ClosePositionPreviewModal
          isOpen={isCloseModalOpen}
          onClose={handleCloseModal}
          tokenId={selectedTokenId}
        />
      )}
    </>
  );
}
