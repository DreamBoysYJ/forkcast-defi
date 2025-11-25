export const strategyLensAbi = [
  {
    type: "constructor",
    inputs: [
      { name: "_admin", type: "address", internalType: "address" },
      {
        name: "_aaveAddressesProvider",
        type: "address",
        internalType: "address",
      },
      { name: "_aavePool", type: "address", internalType: "address" },
      {
        name: "_aaveDataProvdier",
        type: "address",
        internalType: "address",
      },
      {
        name: "_accountFactory",
        type: "address",
        internalType: "address",
      },
      { name: "_aaveOracle", type: "address", internalType: "address" },
      {
        name: "_uniPoolManager",
        type: "address",
        internalType: "address",
      },
      {
        name: "_uniPositionManager",
        type: "address",
        internalType: "address",
      },
      {
        name: "_strategyRouter",
        type: "address",
        internalType: "address",
      },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "AAVE_ADDRESSES_PROVIDER",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IPoolAddressesProvider",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "AAVE_DATA_PROVIDER",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IAaveProtocolDataProvider",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "AAVE_ORACLE",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IPriceOracleGetter",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "AAVE_POOL",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "contract IPool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "ACCOUNT_FACTORY",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract AccountFactory",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "STRATEGY_ROUTER",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract StrategyRouter",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "UNI_POOL_MANAGER",
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
    name: "UNI_POSITION_MANAGER",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IPositionManager",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "admin",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAllAaveReserves",
    inputs: [],
    outputs: [
      {
        name: "reserves",
        type: "tuple[]",
        internalType: "struct StrategyLens.ReserveStaticData[]",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          { name: "symbol", type: "string", internalType: "string" },
          {
            name: "decimals",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "ltv", type: "uint256", internalType: "uint256" },
          {
            name: "liquidationThreshold",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "liquidationBonus",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "reserveFactor",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "usageAsCollateralEnabled",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "borrowingEnabled",
            type: "bool",
            internalType: "bool",
          },
          {
            name: "stableBorrowRateEnabled",
            type: "bool",
            internalType: "bool",
          },
          { name: "isActive", type: "bool", internalType: "bool" },
          { name: "isFrozen", type: "bool", internalType: "bool" },
          {
            name: "borrowCap",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "supplyCap",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "aToken", type: "address", internalType: "address" },
          {
            name: "stableDebtToken",
            type: "address",
            internalType: "address",
          },
          {
            name: "variableDebtToken",
            type: "address",
            internalType: "address",
          },
          { name: "paused", type: "bool", internalType: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAllReserveRates",
    inputs: [],
    outputs: [
      {
        name: "rates",
        type: "tuple[]",
        internalType: "struct StrategyLens.ReserveRateData[]",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          { name: "symbol", type: "string", internalType: "string" },
          {
            name: "liquidityRateRay",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "variableBorrowRateRay",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "stableBorrowRateRay",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAssetPrice",
    inputs: [{ name: "asset", type: "address", internalType: "address" }],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getAssetsPrices",
    inputs: [{ name: "assets", type: "address[]", internalType: "address[]" }],
    outputs: [
      {
        name: "prices",
        type: "tuple[]",
        internalType: "struct StrategyLens.AssetPriceData[]",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          {
            name: "priceInBaseCurrency",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getOracleBaseCurrency",
    inputs: [],
    outputs: [
      {
        name: "baseCurrency",
        type: "address",
        internalType: "address",
      },
      { name: "baseUnit", type: "uint256", internalType: "uint256" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getReserveRates",
    inputs: [{ name: "asset", type: "address", internalType: "address" }],
    outputs: [
      {
        name: "r",
        type: "tuple",
        internalType: "struct StrategyLens.ReserveRateData",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          { name: "symbol", type: "string", internalType: "string" },
          {
            name: "liquidityRateRay",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "variableBorrowRateRay",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "stableBorrowRateRay",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getStrategyPositionView",
    inputs: [{ name: "tokenId", type: "uint256", internalType: "uint256" }],
    outputs: [
      {
        name: "v",
        type: "tuple",
        internalType: "struct StrategyLens.StrategyPositionView",
        components: [
          {
            name: "core",
            type: "tuple",
            internalType: "struct StrategyLens.RouterPositionCore",
            components: [
              {
                name: "owner",
                type: "address",
                internalType: "address",
              },
              {
                name: "vault",
                type: "address",
                internalType: "address",
              },
              {
                name: "supplyAsset",
                type: "address",
                internalType: "address",
              },
              {
                name: "borrowAsset",
                type: "address",
                internalType: "address",
              },
              { name: "isOpen", type: "bool", internalType: "bool" },
            ],
          },
          {
            name: "uniToken0",
            type: "address",
            internalType: "address",
          },
          {
            name: "uniToken1",
            type: "address",
            internalType: "address",
          },
          {
            name: "liquidity",
            type: "uint128",
            internalType: "uint128",
          },
          {
            name: "amount0Now",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "amount1Now",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "tickLower", type: "int24", internalType: "int24" },
          { name: "tickUpper", type: "int24", internalType: "int24" },
          { name: "currentTick", type: "int24", internalType: "int24" },
          {
            name: "sqrtPriceX96",
            type: "uint160",
            internalType: "uint160",
          },
          {
            name: "totalCollateralBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "totalDebtBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "availableBorrowBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "currentLiquidationThreshold",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "ltv", type: "uint256", internalType: "uint256" },
          {
            name: "healthFactor",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUserAaveOverview",
    inputs: [{ name: "user", type: "address", internalType: "address" }],
    outputs: [
      {
        name: "ov",
        type: "tuple",
        internalType: "struct StrategyLens.UserAaveOverview",
        components: [
          { name: "user", type: "address", internalType: "address" },
          { name: "vault", type: "address", internalType: "address" },
          {
            name: "totalCollateralBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "totalDebtBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "availableBorrowBase",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "currentLiquidationThreshold",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "ltv", type: "uint256", internalType: "uint256" },
          {
            name: "healthFactor",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUserReservePositions",
    inputs: [
      { name: "user", type: "address", internalType: "address" },
      { name: "assets", type: "address[]", internalType: "address[]" },
    ],
    outputs: [
      {
        name: "positions",
        type: "tuple[]",
        internalType: "struct StrategyLens.UserReservePosition[]",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          {
            name: "aTokenBalance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "stableDebt",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "variableDebt",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUserReservePositionsAll",
    inputs: [{ name: "user", type: "address", internalType: "address" }],
    outputs: [
      {
        name: "positions",
        type: "tuple[]",
        internalType: "struct StrategyLens.UserReservePosition[]",
        components: [
          { name: "asset", type: "address", internalType: "address" },
          {
            name: "aTokenBalance",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "stableDebt",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "variableDebt",
            type: "uint256",
            internalType: "uint256",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUserUniPosition",
    inputs: [
      { name: "user", type: "address", internalType: "address" },
      { name: "tokenId", type: "uint256", internalType: "uint256" },
    ],
    outputs: [
      {
        name: "ov",
        type: "tuple",
        internalType: "struct StrategyLens.UniPositionOverview",
        components: [
          { name: "token0", type: "address", internalType: "address" },
          { name: "token1", type: "address", internalType: "address" },
          {
            name: "liquidity",
            type: "uint128",
            internalType: "uint128",
          },
          {
            name: "amount0Now",
            type: "uint256",
            internalType: "uint256",
          },
          {
            name: "amount1Now",
            type: "uint256",
            internalType: "uint256",
          },
          { name: "tickLower", type: "int24", internalType: "int24" },
          { name: "tickUpper", type: "int24", internalType: "int24" },
          { name: "currentTick", type: "int24", internalType: "int24" },
          {
            name: "sqrtPriceX96",
            type: "uint160",
            internalType: "uint160",
          },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getUserVault",
    inputs: [{ name: "user", type: "address", internalType: "address" }],
    outputs: [{ name: "vault", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
] as const;
