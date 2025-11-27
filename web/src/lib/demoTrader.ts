// src/lib/demoTrader.ts
import "server-only";

import {
  createPublicClient,
  createWalletClient,
  http,
  parseUnits,
  decodeEventLog,
} from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

import { erc20Abi } from "@/abi/erc20Abi";
import { miniV4SwapRouterAbi } from "@/abi/MiniV4SwapRouterAbi";

// ✅ 서버용 ENV
const rpcUrl = process.env.RPC_URL!;
const demoPk = process.env.DEMO_TRADER_PRIVATE_KEY!;

const MINI_SWAP_ROUTER_ADDRESS = process.env
  .MINI_SWAP_ROUTER_ADDRESS as `0x${string}`;
const AAVE_UNDERLYING = process.env.AAVE_UNDERLYING_SEPOLIA as `0x${string}`;
const LINK_UNDERLYING = process.env.LINK_UNDERLYING_SEPOLIA as `0x${string}`;

// ✅ 훅 주소 (.env 에서 HOOK 사용)
const HOOK_ADDRESS = process.env.HOOK as `0x${string}`;

// 🔍 Hook 이벤트용 mini ABI (SwapPriceLogged 만 정의)
const hookAbi = [
  {
    type: "event",
    name: "SwapPriceLogged",
    anonymous: false,
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        indexed: true,
      },
      {
        name: "tick",
        type: "int24",
        indexed: false,
      },
      {
        name: "sqrtPriceX96",
        type: "uint160",
        indexed: false,
      },
      {
        name: "timestamp",
        type: "uint256",
        indexed: false,
      },
    ],
  },
] as const;

// 🔎 프론트/JSON 응답에서 쓸 타입 (BigInt → string)
export type HookSwapEvent = {
  txHash: `0x${string}`;
  poolId: `0x${string}`;
  tick: number;
  sqrtPriceX96: string; // <- JSON 직렬화 위해 string
  timestamp: string; // <- block.timestamp (string)
};

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
  console.log("[demoTrader] hook         :", HOOK_ADDRESS);

  // 🔧 Foundry에서 하던 것처럼: 100 토큰씩 N번 스왑
  const swapCount = 2;
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
  const hookEvents: HookSwapEvent[] = [];

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

    // 2) swapExactInputSingle 호출
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
    console.log("[demoTrader] swap tx    :", swapHash);
    txHashes.push(swapHash);

    const receipt = await publicClient.waitForTransactionReceipt({
      hash: swapHash,
    });

    // 🔍 이 tx 안에서 Hook 컨트랙트 주소만 필터링
    const logsForHook = receipt.logs.filter(
      (log) => log.address.toLowerCase() === HOOK_ADDRESS.toLowerCase()
    );

    for (const log of logsForHook) {
      try {
        const decoded = decodeEventLog({
          abi: hookAbi,
          data: log.data,
          topics: log.topics,
        });

        if (decoded.eventName === "SwapPriceLogged") {
          const { poolId, tick, sqrtPriceX96, timestamp } = decoded.args as any;

          const evt: HookSwapEvent = {
            txHash: swapHash,
            poolId: poolId as `0x${string}`,
            tick: Number(tick),
            sqrtPriceX96: BigInt(sqrtPriceX96).toString(),
            timestamp: BigInt(timestamp).toString(),
          };

          console.log("[demoTrader] 🔔 Hook SwapPriceLogged:", evt);
          hookEvents.push(evt);
        }
      } catch (err) {
        console.error(
          "[demoTrader] decodeEventLog error for tx",
          swapHash,
          err
        );
      }
    }
  }

  // ✅ 이제 이 객체는 BigInt가 없어서 NextResponse.json에 바로 넣어도 됨
  return {
    blockNumber: blockNumber.toString(),
    swaps: swapCount,
    txHashes,
    hookEvents,
  };
}
