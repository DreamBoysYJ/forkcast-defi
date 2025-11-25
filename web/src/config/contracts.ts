import { sepolia } from "viem/chains";

export const CHAINS = {
  sepolia,
} as const;

export const CONTRACT_ADDRESSES = {
  strategyRouter: process.env.NEXT_PUBLIC_STRATEGY_ROUTER_ADDRESS,
  strategyLens: process.env.NEXT_PUBLIC_STRATEGY_LENS_ADDRESS,
  aaveDataProvider: process.env
    .NEXT_PUBLIC_AAVE_PROTOCOL_DATA_PROVIDER as `0x${string}`,
} as const;
