"use client";

import type { ReactNode } from "react";

type ModalBaseProps = {
  isOpen: boolean;
  onClose: () => void;
  title?: string;
  subtitle?: string;
  children: ReactNode;
};

export function ModalBase({
  isOpen,
  onClose,
  title,
  subtitle,
  children,
}: ModalBaseProps) {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-slate-950/70 backdrop-blur-sm">
      {/* 클릭하면 닫히는 오버레이 */}
      <div className="absolute inset-0" onClick={onClose} aria-hidden="true" />

      {/* 실제 모달 박스 */}
      <div className="relative z-50 w-full max-w-xl rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-2xl">
        {(title || subtitle) && (
          <div className="mb-4 flex items-start justify-between gap-4">
            <div>
              {title && (
                <h2 className="text-sm font-semibold text-slate-50">{title}</h2>
              )}
              {subtitle && (
                <p className="mt-1 text-xs text-slate-400">{subtitle}</p>
              )}
            </div>

            <button
              type="button"
              onClick={onClose}
              className="rounded-full border border-slate-700 px-2 py-1 text-[11px] text-slate-400 hover:bg-slate-800"
            >
              Esc
            </button>
          </div>
        )}

        {children}
      </div>
    </div>
  );
}
