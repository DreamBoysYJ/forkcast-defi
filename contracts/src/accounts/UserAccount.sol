// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {
    IERC721
} from "v4-core/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {
    IPoolAddressesProvider
} from "../interfaces/aave-v3/IPoolAddressesProvider.sol";

/// @title UserAccount
/// @notice Per-user vault contract that actually owns Aave positions and Uniswap v4 LP NFTs.
/// @dev
/// - Deployed once per user via AccountFactory
/// - `owner` is the end user (EOA)
/// - `operator` is typically the StrategyRouter
/// - All Aave supply/borrow state is held under this contract's address
/// - Uniswap v4 LP positions (NFTs) are owned by this contract and approved to the operator
contract UserAccount {
    /// @notice EOA that owns this vault and can override the operator if needed.
    address public owner;

    /// @notice StrategyRouter (or other orchestrator) that is allowed to operate this vault.
    address public operator;

    /// @notice Factory that deployed this vault. Only the factory can call `init`.
    address public immutable factory;

    /// @notice Aave V3 PoolAddressesProvider used to resolve the current Pool address.
    IPoolAddressesProvider public immutable provider;

    // =========
    // Errors
    // =========
    error NotOwner();
    error NotAuthorized();
    error AlreadyInitialized();
    error ZeroAddress();
    error ZeroAmount();
    error ApproveFailed();
    error NotFactory();

    // =========
    // Modifiers
    // =========

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @dev Restricts access to either the owner or the operator.
    /// @dev Used for all “vault operation” functions.
    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner && msg.sender != operator)
            revert NotAuthorized();
        _;
    }

    /// @dev Restricts access to the factory that deployed this vault.
    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    // =========
    // Constructor / init
    // =========

    /// @notice Sets the immutable factory and Aave provider.
    /// @dev Vault is "wired" to a specific factory + Aave deployment.
    /// @param _factory AccountFactory that deploys and initializes this vault.
    /// @param _provider Aave PoolAddressesProvider used to look up the Pool.
    constructor(address _factory, address _provider) {
        if (_factory == address(0) || _provider == address(0))
            revert ZeroAddress();
        factory = _factory;
        provider = IPoolAddressesProvider(_provider);
    }

    /// @notice One-time initialization of owner and operator, callable only by the factory.
    /// @dev
    /// - `owner` is the EOA user
    /// - `operator` is expected to be the StrategyRouter
    /// - Can only be called once per vault
    /// @param _owner The EOA that owns this vault.
    /// @param _operator The router (or other orchestrator) allowed to operate on behalf of the owner.
    function init(address _owner, address _operator) external onlyFactory {
        if (owner != address(0)) revert AlreadyInitialized();
        if (_owner == address(0) || _operator == address(0))
            revert ZeroAddress();
        owner = _owner;
        operator = _operator;
    }

    // =========
    // Internal helpers
    // =========

    /// @dev Convenience helper to fetch the current Aave Pool from the provider.
    function _pool() internal view returns (IPool) {
        return IPool(provider.getPool());
    }

    // =========
    // Aave operations
    // =========

    /// @notice Supply a given `asset` into Aave V3 under this vault.
    /// @dev
    /// - Uses the Aave Pool resolved via `provider`
    /// - Resets allowance to 0 first to avoid non-standard ERC20 issues
    /// - Caller must be `owner` or `operator`
    /// @param asset ERC20 collateral asset to supply.
    /// @param amount Amount of `asset` to supply.
    function supply(
        address asset,
        uint256 amount
    ) external onlyOperatorOrOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (!IERC20(asset).approve(address(_pool()), 0)) revert ApproveFailed();
        if (!IERC20(asset).approve(address(_pool()), amount))
            revert ApproveFailed();

        _pool().supply(asset, amount, address(this), 0);
    }

    /// @notice Borrow a given `asset` from Aave V3 under this vault as debt.
    /// @dev
    /// - Caller must be `owner` or `operator`
    /// - Interest rate mode is hard-coded to variable (2)
    /// @param asset ERC20 asset to borrow.
    /// @param amount Amount of `asset` to borrow.
    function borrow(
        address asset,
        uint256 amount
    ) external onlyOperatorOrOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _pool().borrow(asset, amount, 2, 0, address(this));
    }

    /// @notice Move tokens from this vault to the current operator.
    /// @dev
    /// - Usually used after borrowing to send funds to StrategyRouter for swaps / LP
    /// - Caller must be `owner` or `operator`
    /// @param asset ERC20 token to transfer.
    /// @param amount Amount to send to the operator.
    function pullToOperator(
        address asset,
        uint256 amount
    ) external onlyOperatorOrOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(asset).transfer(operator, amount);
    }

    /// @notice Read the current Aave account data for this vault.
    /// @dev Direct proxy to `IPool.getUserAccountData(address(this))`.
    /// @return totalCollateralBase Total collateral, in Aave base currency units.
    /// @return totalDebtBase Total debt, in Aave base currency units.
    /// @return availableBorrowsBase Available borrowing power, in Aave base currency units.
    /// @return currentLiquidationThreshold Current liquidation threshold (basis points).
    /// @return ltv Current loan-to-value ratio (basis points).
    /// @return healthFactor Current health factor (1e18 precision).
    function getMyAaveData()
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return _pool().getUserAccountData(address(this));
    }

    /// @notice Approve an operator (e.g. StrategyRouter) to manage all Uniswap v4 LP NFTs.
    /// @dev
    /// - Wraps `IERC721(positionManager).setApprovalForAll(_operator, true)`
    /// - Called from the router once, typically right after LP mint
    /// @param positionManager Uniswap v4 PositionManager contract.
    /// @param _operator Address to grant NFT management rights to.
    function approveUniswapV4Operator(
        address positionManager,
        address _operator
    ) external onlyOperatorOrOwner {
        IERC721(positionManager).setApprovalForAll(_operator, true);
    }

    /// @notice Repay a given `asset` debt on Aave V3 from this vault.
    /// @dev
    /// - Uses the same approve(0) → approve(amount) pattern as `supply`
    /// - Caller must be `owner` or `operator`
    /// @param asset ERC20 debt asset to repay.
    /// @param amount Repay amount.
    function repay(address asset, uint256 amount) external onlyOperatorOrOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        // Aave approve
        if (!IERC20(asset).approve(address(_pool()), 0)) revert ApproveFailed();
        if (!IERC20(asset).approve(address(_pool()), amount))
            revert ApproveFailed();

        _pool().repay(asset, amount, 2, address(this));
    }

    /// @notice Withdraw a given `asset` from Aave to an external address.
    /// @dev
    /// - Caller must be `owner` or `operator`
    /// - Aave withdraw can return less than `amount` if not fully available
    /// @param asset ERC20 collateral asset to withdraw.
    /// @param amount Requested withdraw amount.
    /// @param to Recipient of the withdrawn tokens.
    /// @return amountOut Actual amount withdrawn by Aave.
    function withdrawTo(
        address asset,
        uint256 amount,
        address to
    ) external onlyOperatorOrOwner returns (uint256 amountOut) {
        if (asset == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        amountOut = _pool().withdraw(asset, amount, to);
    }
}
