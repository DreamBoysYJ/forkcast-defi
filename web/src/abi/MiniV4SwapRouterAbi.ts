export const miniV4SwapRouterAbi = [
  {
    type: "constructor",
    inputs: [
      { name: "_poolManager", type: "address", internalType: "address" },
    ],
    stateMutability: "nonpayable",
  },
  { type: "receive", stateMutability: "payable" },
  {
    type: "function",
    name: "poolManager",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IPoolManager",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "swapExactInputSingle",
    inputs: [
      {
        name: "params",
        type: "tuple",
        internalType: "struct Miniv4SwapRouter.ExactInputSingleParams",
        components: [
          {
            name: "poolKey",
            type: "tuple",
            internalType: "struct PoolKey",
            components: [
              {
                name: "currency0",
                type: "address",
                internalType: "Currency",
              },
              {
                name: "currency1",
                type: "address",
                internalType: "Currency",
              },
              { name: "fee", type: "uint24", internalType: "uint24" },
              {
                name: "tickSpacing",
                type: "int24",
                internalType: "int24",
              },
              {
                name: "hooks",
                type: "address",
                internalType: "contract IHooks",
              },
            ],
          },
          { name: "zeroForOne", type: "bool", internalType: "bool" },
          {
            name: "amountIn",
            type: "uint128",
            internalType: "uint128",
          },
          {
            name: "amountOutMin",
            type: "uint128",
            internalType: "uint128",
          },
          { name: "hookData", type: "bytes", internalType: "bytes" },
        ],
      },
    ],
    outputs: [{ name: "amountOut", type: "uint256", internalType: "uint256" }],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "unlockCallback",
    inputs: [{ name: "data", type: "bytes", internalType: "bytes" }],
    outputs: [{ name: "", type: "bytes", internalType: "bytes" }],
    stateMutability: "nonpayable",
  },
  {
    type: "error",
    name: "UnsupportedAction",
    inputs: [{ name: "action", type: "uint256", internalType: "uint256" }],
  },
] as const;
