"use client";

import { useEffect, useState, type ReactNode } from "react";

export function ClientOnly({ children }: { children: ReactNode }) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Server Render + First Client Render -> Null
  if (!mounted) return null;

  // After then Render Real UI
  return <>{children}</>;
}
