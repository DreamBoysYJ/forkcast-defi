// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UserAccount} from "../accounts/UserAccount.sol";

/// @title AccountFactory
/// @notice Deploys and registers per-user UserAccount vaults.
/// @dev
/// - One UserAccount per EOA owner
/// - Stores a global mapping owner → vault
/// - Also wires each vault to the configured Aave AddressesProvider
/// - In this project, the StrategyRouter is expected to be the main caller
contract AccountFactory {
    /// @notice Aave PoolAddressesProvider address used by all UserAccount instances.
    /// @dev Passed to each new UserAccount so it can resolve the Aave Pool.
    address public immutable provider;

    /// @notice Mapping from EOA owner → UserAccount vault.
    /// @dev Returns address(0) if the user has no vault yet.
    mapping(address => address) public accountOf;

    event AccountCreated(
        address indexed owner,
        address indexed account,
        address indexed operator
    );

    error Exists();
    error ZeroAddress();

    /// @param _provider Aave PoolAddressesProvider used by all UserAccount vaults.
    constructor(address _provider) {
        if (_provider == address(0)) revert ZeroAddress();
        provider = _provider;
    }

    /// @notice Returns the existing vault for `_owner`, or lazily creates one.
    /// @dev
    /// - Intended to be called by the StrategyRouter
    /// - `operator` for the new vault is set to `msg.sender`
    /// - If the vault already exists, it is simply returned
    /// @param _owner EOA that should own the UserAccount vault.
    /// @return userAccount The existing or newly created UserAccount address.
    function getOrCreate(
        address _owner
    ) external returns (address userAccount) {
        if (_owner == address(0)) revert ZeroAddress();

        userAccount = accountOf[_owner];

        // Lazily deploy a new vault if this owner has none yet.
        if (userAccount == address(0)) {
            userAccount = address(new UserAccount(address(this), provider));
            UserAccount(userAccount).init(_owner, msg.sender);
            accountOf[_owner] = userAccount;
            emit AccountCreated(_owner, userAccount, msg.sender);
        }
    }
}
