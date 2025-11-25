import { CONTRACT_ADDRESSES, CHAINS } from "@/config/contracts";
import { strategyLensAbi } from "@/abi/StrategyLens";
import { aaveDataProviderAbi } from "@/abi/aaveDataProviderAbi";
import { strategyRouterAbi } from "@/abi/StrategyRouter";

export const strategyLensContract = {
  address: CONTRACT_ADDRESSES.strategyLens as `0x${string}`,
  abi: strategyLensAbi,
  chainId: CHAINS.sepolia.id,
} as const;

export const aaveDataProviderContract = {
  address: CONTRACT_ADDRESSES.aaveDataProvider as `0x${string}`,
  abi: aaveDataProviderAbi,
  chainId: CHAINS.sepolia.id,
} as const;

export const strategyRouterContract = {
  address: CONTRACT_ADDRESSES.strategyRouter as `0x${string}`,
  abi: strategyRouterAbi,
  chainId: CHAINS.sepolia.id,
};
