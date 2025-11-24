// src/components/modals/DemoTraderModal.tsx
"use client";

type DemoTraderModalProps = {
  isOpen: boolean;
  onClose: () => void;
};

export function DemoTraderModal({ isOpen, onClose }: DemoTraderModalProps) {
  if (!isOpen) return null;

  const handleRunDemo = async () => {
    // TODO: 여기서 실제 demo trader 스왑 트랜잭션(or 백엔드 호출) 연결
    console.log("[TODO] run demo trader swaps (fake volume)");
  };

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70">
      <div className="w-full max-w-xl rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-xl">
        {/* 헤더 */}
        <div className="mb-4 flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold text-slate-50">
              Demo trader – simulate swap volume
            </h2>
            <p className="text-xs text-slate-400">
              Run a fake trader that performs swaps on your Uniswap v4 pool to
              generate LP fees (Sepolia only).
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"
          >
            Esc
          </button>
        </div>

        {/* 본문 */}
        <div className="space-y-3 text-sm text-slate-100">
          <p>
            This demo trader will send a series of small swaps through your
            AAVE/WBTC pool on Sepolia. The goal is to create visible LP fees for
            your one-shot position.
          </p>
          <ul className="list-disc space-y-1 pl-5 text-xs text-slate-300">
            <li>Only runs on testnet (Sepolia).</li>
            <li>Targets the same pool used by your strategy position.</li>
            <li>Your LP position should see accumulated fees after a while.</li>
          </ul>
          <p className="text-[11px] text-slate-500">
            This is for demo only – it does not guarantee profit and should not
            be used on mainnet.
          </p>
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
            onClick={handleRunDemo}
            className="rounded-full bg-indigo-500 px-5 py-2 text-xs font-semibold text-slate-950 hover:bg-indigo-400"
          >
            Run demo swaps
          </button>
        </div>
      </div>
    </div>
  );
}
