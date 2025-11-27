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

// -------------------------------
// 1) 공용(프론트+서버) 주소 계열 env
//    → NEXT_PUBLIC_* 만 사용 (이미 .env.production 에 있음)
// -------------------------------
const MINI_SWAP_ROUTER_ADDRESS = process.env
  .NEXT_PUBLIC_MINI_SWAP_ROUTER_ADDRESS as `0x${string}`;

const AAVE_UNDERLYING = process.env
  .NEXT_PUBLIC_AAVE_UNDERLYING_SEPOLIA as `0x${string}`;

const LINK_UNDERLYING = process.env
  .NEXT_PUBLIC_LINK_UNDERLYING_SEPOLIA as `0x${string}`;

const HOOK_ADDRESS = process.env.NEXT_PUBLIC_HOOK as `0x${string}`;

// -------------------------------
// 2) Hook 이벤트 mini ABI
// -------------------------------
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
  sqrtPriceX96: string; // JSON 직렬화 위해 string
  timestamp: string; // block.timestamp (string)
};

// -------------------------------
// 3) 서버 전용 설정/클라이언트 헬퍼
//    → 여기서만 DEMO_TRADER_PRIVATE_KEY / RPC_URL 읽음
// -------------------------------
// -------------------------------
// 3) 서버 전용 설정/클라이언트 헬퍼
//    → 여기서만 DEMO_TRADER_PRIVATE_KEY / ALCHEMY_RPC_URL 읽음
// -------------------------------
function getServerClients() {
  // 1순위: Alchemy (백엔드 전용)
  // 2순위: RPC_URL (로컬에서 Infura 등)
  // 3순위: NEXT_PUBLIC_RPC_URL (혹시라도 세팅만 돼 있다면)
  const rpcUrl =
    process.env.ALCHEMY_RPC_URL ||
    process.env.RPC_URL ||
    process.env.NEXT_PUBLIC_RPC_URL ||
    undefined;

  const demoPk = process.env.DEMO_TRADER_PRIVATE_KEY;
  console.log("[demoTrader] rpcUrl ", rpcUrl);

  if (!rpcUrl) {
    throw new Error(
      "ALCHEMY_RPC_URL (or RPC_URL / NEXT_PUBLIC_RPC_URL) env not set on server for demo trader"
    );
  }
  if (!demoPk) {
    throw new Error("DEMO_TRADER_PRIVATE_KEY env not set on server");
  }

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

  return { publicClient, walletClient, account };
}

// -------------------------------
// 4) demo trade 한번 실행하는 메인 함수
// -------------------------------
export async function runDemoTrade() {
  // 주소 계열 env 체크 (NEXT_PUBLIC_* 이라 빌드 타임에도 존재해야 함)
  if (
    !MINI_SWAP_ROUTER_ADDRESS ||
    !AAVE_UNDERLYING ||
    !LINK_UNDERLYING ||
    !HOOK_ADDRESS
  ) {
    throw new Error("Missing NEXT_PUBLIC_* env vars for demo trader");
  }

  // 서버 전용 클라이언트 준비 (여기서만 private key / RPC 읽음)
  const { publicClient, walletClient, account } = getServerClients();

  const blockNumber = await publicClient.getBlockNumber();
  console.log("[demoTrader] current block :", blockNumber.toString());
  console.log("[demoTrader] trader       :", account.address);
  console.log("[demoTrader] hook         :", HOOK_ADDRESS);

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

  // ✅ BigInt 없이 JSON 직렬화 가능한 응답
  return {
    blockNumber: blockNumber.toString(),
    swaps: swapCount,
    txHashes,
    hookEvents,
  };
}
