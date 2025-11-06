// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPool} from "../interfaces/aave-v3/IPool.sol";

contract UserAccount {
    address public owner;
    IPool public aavePool;

    error NotOwner();
    error AlreadyInitialized();
    error ZeroAddress();
    error ZeroAmount();
    error ApproveFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function init(address _owner, address _aavePool) external {
        if (owner != address(0)) revert AlreadyInitialized();
        owner = _owner;
        aavePool = IPool(_aavePool);
    }

    function supply(address asset, uint256 amount) external {
        if (asset == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (!IERC20(asset).approve(address(aavePool), 0))
            revert ApproveFailed();
        if (!IERC20(asset).approve(address(aavePool), amount))
            revert ApproveFailed();

        aavePool.supply(asset, amount, address(this), 0);
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
        return aavePool.getUserAccountData(address(this));
    }
}
