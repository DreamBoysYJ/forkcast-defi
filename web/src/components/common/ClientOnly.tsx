"use client";

import { useEffect, useState, type ReactNode } from "react";

export function ClientOnly({ children }: { children: ReactNode }) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  // 서버 렌더 + 첫 클라이언트 렌더에서는 null (아무 것도 안 그림)
  if (!mounted) return null;

  // 그 다음부터 실제 UI 렌더
  return <>{children}</>;
}
