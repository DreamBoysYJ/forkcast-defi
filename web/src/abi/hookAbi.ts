export const hookAbi = [
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
