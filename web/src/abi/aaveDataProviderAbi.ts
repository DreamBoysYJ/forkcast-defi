// src/abi/aaveDataProviderAbi.ts

export const aaveDataProviderAbi = [
  {
    type: "function",
    name: "getReserveData",
    stateMutability: "view",
    inputs: [
      {
        name: "asset",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [
      {
        name: "unbacked",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "accruedToTreasuryScaled",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "totalAToken",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "totalStableDebt",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "totalVariableDebt",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "liquidityRate",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "variableBorrowRate",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "stableBorrowRate",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "averageStableBorrowRate",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "liquidityIndex",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "variableBorrowIndex",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "lastUpdateTimestamp",
        type: "uint40",
        internalType: "uint40",
      },
    ],
  },
] as const;
