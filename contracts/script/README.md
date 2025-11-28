# Scripts

This folder contains all Foundry scripts used to deploy and bootstrap the
Forkcast DeFi demo on Sepolia.

They are not 'one big monolithic deploy script' - instead, each script
hadnles a small, well-defined step.
This makes it easier to re-run only the part that changed.

## Prerequisites

- Network : Sepolia
- Foundry installed ('forge', 'cast')
- '.env' configured as you can see in .env.example

All scripts are written as Foundry 'Script' contracts and are expected to be
executed via `forge script` with `--rpc-url` and `--broadcast`.

## Script catalogs

- `DeployCors.s.sol` - Deploy core contracts (MiniV4SwapRouter, AccountFactory, StrategyRouter, StrategyLens) in right order.
- `DeployHookFactory.s.sol` - Deploy Uniswap v4 hook factory contract.
- `DeploySwapPriceLoggerHook.s.sol` - Deploy Uniswap v4 hook contract through HookFactory contract.
- `InitAaveLinkHookedPool.s.sol` - Init AAVE/LINK hooked v4 pool.
- `InitStrategyRouterPermit2.s.sol` - allow StrategyRouter to approve for Permit2 and Uniswap v4 Pool Manager.
- `InitStrategyRouterV4PoolConfig.s.sol` - Set config variables for strategyRouter. (ex. poolKey, initTick...)

## Deployment flows

1. **Deploy core contracts**

   ```bash
   forge script script/DeployCore.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```

2. **Deploy Hook factory**

   ```bash
   forge script script/DeployHookFactory.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```

3. **Deploy the logging hook through Hook Facgtory**

   ```bash
   forge script script/DeploySwapPriceLoggerHook.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```

4. **Init the hooked AAVE/LINK Pool**

   ```bash
   forge script script/InitAaveLinkHookedPool.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```

5. **Call setConfig.() in strategyRouter**

   ```bash
   forge script script/InitStrategyRouterV4PoolConfig.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```

6. **Call initPermit2() in strategyRouter**

   ```bash
   forge script script/InitStrategyRouterPermit2.s.sol \
     --rpc-url sepolia \
     --broadcast
   ```
