### `old_test/` – archived router experiments

This folder contains **early unit tests** that were written while
incrementally designing the `StrategyRouter`:

- `StrategyRouter_AaveSupply.t.sol`  
  First pass at testing the “supply into Aave” leg in isolation.
- `StrategyRouter_AaveBorrow.t.sol`  
  Focused on borrow guards, caps and base → asset conversion logic.
- `StrategyRouter_PreviewBorrow.t.sol`  
  Prototype tests for the original `previewBorrow` math and edge cases.

These tests were extremely helpful while iterating on the router,
but the on-chain design has evolved since then.  
They are kept **as historical references** and are **not guaranteed to
compile or pass against the current contracts**.

Treat them as:

- design notes for how the borrow/supply/preview logic evolved, and
- a scratchpad to revisit if we refactor the router math again.

They are **excluded from the main test suite** – regular `forge test`
only needs the tests under `test/` (outside of `old_test/`).
