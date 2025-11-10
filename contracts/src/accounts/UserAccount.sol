// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";
import {
    IPoolAddressesProvider
} from "../interfaces/aave-v3/IPoolAddressesProvider.sol";

contract UserAccount {
    address public owner;
    address public operator;
    address public immutable factory;
    IPoolAddressesProvider public immutable provider;

    error NotOwner();
    error NotAuthorized();
    error AlreadyInitialized();
    error ZeroAddress();
    error ZeroAmount();
    error ApproveFailed();
    error NotFactory();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner && msg.sender != operator)
            revert NotAuthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    constructor(address _factory, address _provider) {
        if (_factory == address(0) || _provider == address(0))
            revert ZeroAddress();
        factory = _factory;
        provider = IPoolAddressesProvider(_provider);
    }

    function init(address _owner, address _operator) external onlyFactory {
        if (owner != address(0)) revert AlreadyInitialized();
        if (_owner == address(0) || _operator == address(0))
            revert ZeroAddress();
        owner = _owner;
        operator = _operator;
    }

    function _pool() internal view returns (IPool) {
        return IPool(provider.getPool());
    }

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

    function borrow(
        address asset,
        uint256 amount
    ) external onlyOperatorOrOwner {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _pool().borrow(asset, amount, 2, 0, address(this));
    }

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
}
