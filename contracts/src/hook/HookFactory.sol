// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SwapPriceLoggerHook} from "./SwapPriceLoggerHook.sol";

contract HookFactory {
    /// @notice Uniswap v4 PoolManager address
    address public immutable poolManager;

    /// @notice Deploy Hook admin
    address public owner;

    /// @notice 훅이 이미 배포된 salt로 다시 배포 시도
    error AlreadyDeployed(address hook, bytes32 salt);

    /// @notice owner 아닌 계정이 배포 시도
    error NotOwner();

    /// @notice address(0)
    error ZeroAddress();

    /// @notice 예상 주소와 실제 배포 주소 다른 경우
    error HookAddressMismatch(address expected, address actual);

    /// @dev 성공적 배포
    event HookDeployed(address indexed hook, bytes32 salt);

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

    /// @notice 주어진 salt로 배포될 Hook 주소를 미리 계산
    /// @dev    배포 전 중복 여부 체크에 사용
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

    /// @notice HookMiner로 찾은 salt를 사용해 Hook을 CREATE2 배포
    /// @param salt HookMiner.find()로 찾은 값
    /// @return hook 배포된 훅 주소
    function deploySwapPriceLoggerHook(
        bytes32 salt
    ) external onlyOwner returns (address hook) {
        // 예상 주소 계산
        address expected = computeHookAddress(salt);

        // 이미 코드로 올라가 있다면 재사용 salt
        if (expected.code.length != 0) {
            revert AlreadyDeployed(expected, salt);
        }

        // CREATE2 배포 시도
        SwapPriceLoggerHook instance = new SwapPriceLoggerHook{salt: salt}(
            poolManager
        );
        hook = address(instance);

        // CREATE2 공식과 실제 배포 주소 일치하는지 확인
        if (hook != expected) {
            revert HookAddressMismatch(expected, hook);
        }

        emit HookDeployed(hook, salt);
    }
}
