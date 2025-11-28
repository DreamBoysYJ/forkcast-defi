// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SwapPriceLoggerHook} from "./SwapPriceLoggerHook.sol";

/// @title HookFactory
/// @notice Factory for deploying SwapPriceLoggerHook instances via CREATE2 + salt.
/// @dev
/// - All hooks share the same Uniswap v4 PoolManager
/// - Intended to work together with an off-chain HookMiner that searches for nice salts
/// - Off-chain tools can reproduce the same addresses via `computeHookAddress`
contract HookFactory {
    /// @notice Uniswap v4 PoolManager address that all hooks will be wired to.
    address public immutable poolManager;

    /// @notice Admin address that is allowed to deploy new hooks.
    address public owner;

    // --- Errors ---

    /// @notice Thrown when attempting to deploy a hook with a salt that already has code at the predicted address.
    error AlreadyDeployed(address hook, bytes32 salt);

    /// @notice owner 아닌 계정이 배포 시도
    error NotOwner();

    /// @notice address(0)
    error ZeroAddress();

    /// @notice Thrown when the actual CREATE2 deployment address does not match the precomputed one.
    error HookAddressMismatch(address expected, address actual);

    // --- Events ---

    event HookDeployed(address indexed hook, bytes32 salt);

    /// @param _poolManager Uniswap v4 PoolManager that all hooks will attach to.
    /// @param _owner EOA or contract that is authorized to deploy new hooks.
    constructor(address _poolManager, address _owner) {
        if (_poolManager == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        poolManager = _poolManager;
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // --- View helpers ---

    /// @notice Computes the deterministic hook address for a given salt.
    /// @dev
    /// Uses the standard CREATE2 formula with this factory as `deployer`:
    /// `address = bytes20(keccak256(0xff, deployer, salt, keccak256(bytecode)))`.
    /// The bytecode is SwapPriceLoggerHook creation code plus the constructor argument (poolManager).
    /// @param salt Salt discovered off-chain (e.g., by HookMiner).
    /// @return predicted The address where the hook will be deployed if CREATE2 is used with this salt.
    function computeHookAddress(
        bytes32 salt
    ) public view returns (address predicted) {
        bytes memory creationCode = type(SwapPriceLoggerHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager);
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(creationCode, constructorArgs)
        );

        // CREATE2 : keccak256(0xff, deployer, salt, keccak256(bytecode))
        bytes32 data = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)
        );
        predicted = address(uint160(uint256(data)));
    }

    // --- Deploy ---

    /// @notice Deploys a new SwapPriceLoggerHook using CREATE2 and a precomputed salt.
    /// @dev
    /// Deployment flow:
    /// 1. Compute the expected hook address via `computeHookAddress(salt)`.
    /// 2. If there is already code at that address, revert with `AlreadyDeployed`.
    /// 3. Deploy the hook via CREATE2 using the same salt.
    /// 4. Ensure that the deployed address matches the predicted one; otherwise revert.
    /// 5. Emit `HookDeployed(hook, salt)` for off-chain indexers and UIs.
    ///
    /// @param salt Salt value (for CREATE2) typically discovered off-chain by HookMiner.
    /// @return hook The address of the newly deployed hook.
    function deploySwapPriceLoggerHook(
        bytes32 salt
    ) external onlyOwner returns (address hook) {
        // 1) Compute the deterministic address for this salt
        address expected = computeHookAddress(salt);

        // 2) If code already exists at that address, the salt is considered taken
        if (expected.code.length != 0) {
            revert AlreadyDeployed(expected, salt);
        }

        // 3) Deploy the hook via CREATE2, wiring it to the known PoolManager
        SwapPriceLoggerHook instance = new SwapPriceLoggerHook{salt: salt}(
            poolManager
        );
        hook = address(instance);

        // 4) Sanity check — runtime address must match the CREATE2 prediction
        if (hook != expected) {
            revert HookAddressMismatch(expected, hook);
        }

        emit HookDeployed(hook, salt);
    }
}
