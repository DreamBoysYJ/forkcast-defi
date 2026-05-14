"use client";
import { useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi";

export default function Connect() {
  const { address, isConnected } = useAccount();
  const { connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  // 👇 하이드레이션 불일치 방지용
  const [mounted, setMounted] = useState(false);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    // 초기 SSR ↔ CSR 불일치 방지: 스켈레톤/빈 상태
    return (
      <button className="border rounded px-3 py-2" suppressHydrationWarning>
        Connect
      </button>
    );
  }

  return isConnected ? (
    <button className="border rounded px-3 py-2" onClick={() => disconnect()}>
      Disconnect {address?.slice(0, 6)}…{address?.slice(-4)}
    </button>
  ) : (
    <button
      className="border rounded px-3 py-2"
      onClick={() => connect({ connector: injected() })}
      disabled={isPending}
    >
      {isPending ? "Connecting…" : "Connect MetaMask"}
    </button>
  );
}
