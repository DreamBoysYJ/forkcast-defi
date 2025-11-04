import { http, createConfig } from "wagmi";
import { sepolia } from "viem/chains";
import { injected } from "wagmi";

export const config = createConfig({
  chains: [sepolia],
  connectors: [injected()],
  transports: { [sepolia.id]: http(process.env.NEXT_PUBLIC_RPC_URL!) },
});
