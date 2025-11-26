// src/lib/demoTrader.ts
import "server-only";
import { createPublicClient, createWalletClient, http, parseUnits } from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

// ✅ 이미 서버용 ENV 들 (.env.local)에 있음
const rpcUrl = process.env.RPC_URL!;
const demoPk = process.env.DEMO_TRADER_PRIVATE_KEY!;

const MINI_SWAP_ROUTER_ADDRESS = process.env
  .MINI_SWAP_ROUTER_ADDRESS as `0x${string}`;
const AAVE_UNDERLYING = process.env.AAVE_UNDERLYING_SEPOLIA as `0x${string}`;
const LINK_UNDERLYING = process.env.LINK_UNDERLYING_SEPOLIA as `0x${string}`;
const HOOK_ADDRESS = process.env.HOOK as `0x${string}`;

// ✅ 너 프로젝트에 이미 있는 ABI 경로에 맞춰서 import
import { erc20Abi } from "@/abi/erc20Abi";
import { miniV4SwapRouterAbi } from "@/abi/MiniV4SwapRouterAbi";

// trader 계정 & 클라이언트
const account = privateKeyToAccount(demoPk as `0x${string}`);

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(rpcUrl),
});

const walletClient = createWalletClient({
  chain: sepolia,
  transport: http(rpcUrl),
  account,
});

// demo trade 한번 실행하는 함수
export async function runDemoTrade() {
  if (
    !rpcUrl ||
    !demoPk ||
    !MINI_SWAP_ROUTER_ADDRESS ||
    !AAVE_UNDERLYING ||
    !LINK_UNDERLYING ||
    !HOOK_ADDRESS
  ) {
    throw new Error("Missing server-side env vars for demo trader");
  }

  const blockNumber = await publicClient.getBlockNumber();
  console.log("[demoTrader] current block :", blockNumber.toString());
  console.log("[demoTrader] trader       :", account.address);

  // 🔧 Foundry에서 하던 것처럼: 100 토큰씩 5번 스왑
  const swapCount = 4;
  const amountPerSwap = parseUnits("100", 18); // AAVE/LINK 둘 다 18dec 가정

  // PoolKey: Solidity _buildAaveLinkPoolKey 과 동일하게
  const poolKey = {
    currency0: AAVE_UNDERLYING,
    currency1: LINK_UNDERLYING,
    fee: 3000, // uint24
    tickSpacing: 10, // int24
    hooks: HOOK_ADDRESS,
  } as const;

  const txHashes: `0x${string}`[] = [];

  for (let i = 0; i < swapCount; i++) {
    const zeroForOne = i % 2 === 0;
    const inToken = zeroForOne ? AAVE_UNDERLYING : LINK_UNDERLYING;

    console.log(
      `[demoTrader] swap #${
        i + 1
      } | zeroForOne=${zeroForOne} | inToken=${inToken}`
    );

    // 1) inToken → mini router approve
    const approveHash = await walletClient.writeContract({
      abi: erc20Abi,
      address: inToken,
      functionName: "approve",
      args: [MINI_SWAP_ROUTER_ADDRESS, amountPerSwap],
    });
    console.log("[demoTrader] approve tx:", approveHash);
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    // 2) swapExactInputSingle
    const swapHash = await walletClient.writeContract({
      abi: miniV4SwapRouterAbi,
      address: MINI_SWAP_ROUTER_ADDRESS,
      functionName: "swapExactInputSingle",
      args: [
        {
          poolKey,
          zeroForOne,
          amountIn: amountPerSwap,
          amountOutMin: 0n,
          hookData: "0x",
        },
      ],
    });
    console.log("[demoTrader] swap tx:", swapHash);
    txHashes.push(swapHash);
    await publicClient.waitForTransactionReceipt({ hash: swapHash });
  }

  // API 라우트에서 그대로 JSON으로 보내줄 데이터
  return {
    blockNumber: blockNumber.toString(),
    swaps: swapCount,
    txHashes,
  };
}
